require_relative "../base"

module IndividualReport
  class Processor < Base
    SEVERITY_CONFIG = {
      "CRITICAL" => { emoji: "🔴", weight: 0, color: "#dc2626" },
      "HIGH" => { emoji: "🟠", weight: 1, color: "#ea580c" },
      "MEDIUM" => { emoji: "🟡", weight: 2, color: "#ca8a04" },
      "LOW" => { emoji: "🔵", weight: 3, color: "#2563eb" },
      "UNKNOWN" => { emoji: "⚪", weight: 4, color: "#6b7280" },
    }.freeze

    def initialize(input_dir = "out", output_dir = "out", service_name = "")
      @input_dir = input_dir
      @service_name = service_name
      @output_dir = output_dir
      @vulnerabilities = []
      @scan_metadata = {}

      # Ensure output directory exists
      FileUtils.mkdir_p(@output_dir)
    end

    def process
      puts "🔍 Looking for security reports in #{@input_dir}..."
      puts "📂 Current directory: #{Dir.pwd}"
      puts

      find_and_process_reports

      puts "📊 Found #{@vulnerabilities.length} vulnerabilities"
      generate_enhanced_summary
      generate_json_export
      print_quick_stats
    end

    private

    def find_and_process_reports
      report_files = %w[
        docker-scan-trivy.json
        dependency-scan-trivy.json
        trivy-results.json
        security-scan.json
      ]

      find_files(@input_dir, report_files).each do |file|
        puts "📄 Processing #{file}..."
        process_trivy_file(file)
      end
    end

    def find_files(dir, files_to_check)
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "**", "*"))
        .select { |f| File.file?(f) }
        .select { |f| files_to_check.include?(File.basename(f)) }
    end

    def process_trivy_file(file)
      content = File.read(file)
      data = JSON.parse(content)

      # Extract scan metadata
      extract_scan_metadata(data, file)

      # Handle different Trivy JSON structures
      results = extract_results(data)

      results.each { |result| process_trivy_result(result, file) }

      puts "   ✓ Processed #{File.basename(file)}"
    rescue JSON::ParserError => e
      puts "   ⚠️  Invalid JSON in #{file}: #{e.message}"
    rescue => e
      puts "   ⚠️  Error processing #{file}: #{e.message}"
    end

    def extract_scan_metadata(data, file)
      @scan_metadata[file] = {
        schema_version: data["SchemaVersion"],
        artifact_name: data["ArtifactName"],
        artifact_type: data["ArtifactType"],
        scan_time: extract_scan_time(data),
        metadata: data["Metadata"],
      }
    end

    def extract_scan_time(data)
      # Try different time fields that Trivy might use
      time_fields = ["CreatedAt", "Metadata", "timestamp"]
      time_fields.each do |field|
        if data[field]
          return Time.parse(data[field]) rescue nil
        end
      end
      File.mtime(@input_dir) rescue Time.now
    end

    def extract_results(data)
      return data["Results"] if data["Results"]
      return [data] if data["Vulnerabilities"]
      []
    end

    def process_trivy_result(result, source_file)
      return unless result["Vulnerabilities"]

      target = result["Target"] || File.basename(source_file)

      result["Vulnerabilities"].each do |vuln|
        vulnerability = build_vulnerability(vuln, target, source_file)
        @vulnerabilities << vulnerability
      end
    end

    def build_vulnerability(vuln, target, source_file)
      {
        service: @service_name,
        severity: normalize_severity(vuln["Severity"]),
        title: clean_title(vuln["Title"] || vuln["VulnerabilityID"] || "Unknown vulnerability"),
        description: vuln["Description"] || "No description available",
        location: vuln["PkgName"] || target,
        target: target,
        cve: vuln["VulnerabilityID"],
        cvss: extract_cvss_data(vuln),
        fixed_version: vuln["FixedVersion"],
        installed_version: vuln["InstalledVersion"],
        published_date: parse_date(vuln["PublishedDate"]),
        last_modified_date: parse_date(vuln["LastModifiedDate"]),
        references: extract_references(vuln),
        source_file: File.basename(source_file),
        pkg_path: vuln["PkgPath"],
        data_source: vuln["DataSource"],
      }
    end

    def extract_cvss_data(vuln)
      cvss_data = {}

      # Extract CVSS v3 (preferred)
      if vuln["CVSS"] && vuln["CVSS"]["nvd"]
        nvd_cvss = vuln["CVSS"]["nvd"]
        cvss_data[:v3_score] = nvd_cvss["V3Score"]
        cvss_data[:v3_vector] = nvd_cvss["V3Vector"]
      end

      # Extract CVSS v2 as fallback
      if vuln["CVSS"] && vuln["CVSS"]["redhat"]
        rh_cvss = vuln["CVSS"]["redhat"]
        cvss_data[:v2_score] = rh_cvss["V2Score"] unless cvss_data[:v3_score]
        cvss_data[:v2_vector] = rh_cvss["V2Vector"] unless cvss_data[:v3_vector]
      end

      # Try direct CVSS fields
      cvss_data[:v3_score] ||= vuln["CvssScore"] || vuln["CvssV3Score"]
      cvss_data[:v2_score] ||= vuln["CvssV2Score"]

      cvss_data.empty? ? nil : cvss_data
    end

    def extract_references(vuln)
      refs = []
      refs.concat(vuln["References"] || [])
      refs << vuln["PrimaryURL"] if vuln["PrimaryURL"]
      refs.uniq.compact
    end

    def parse_date(date_str)
      return nil unless date_str
      Time.parse(date_str).strftime("%Y-%m-%d")
    rescue
      nil
    end

    def normalize_severity(severity)
      return "UNKNOWN" unless severity
      severity.upcase
    end

    def clean_title(title)
      title.gsub(/^\[[\w\s]+\]\s*/, "").strip
    end

    def severity_config(severity)
      SEVERITY_CONFIG[normalize_severity(severity)] || SEVERITY_CONFIG["UNKNOWN"]
    end

    def count_by_severity
      @vulnerabilities.group_by { |v| v[:severity] }
                      .transform_values(&:count)
    end

    def cvss_severity_from_score(score)
      return "UNKNOWN" unless score

      case score.to_f
      when 9.0..10.0 then "CRITICAL"
      when 7.0...9.0 then "HIGH"
      when 4.0...7.0 then "MEDIUM"
      when 0.1...4.0 then "LOW"
      else "UNKNOWN"
      end
    end

    def generate_enhanced_summary
      output_file = File.join(@output_dir, "security-summary.md")
      File.open(output_file, "w") do |f|
        write_header(f)
        write_executive_summary(f)
        write_severity_breakdown(f)
        write_cvss_analysis(f)
        write_detailed_findings(f)
        write_recommendations(f)
        write_scan_metadata(f)
      end

      puts "✅ Enhanced summary generated: #{output_file}"
    end

    def write_header(f)
      f.puts "# 🛡️ Security Scan Report"
      f.puts
      f.puts "#{@service_name.empty? ? "" : "**Service:** #{@service_name}  "}"
      f.puts "**📅 Generated:** #{Time.now.strftime("%Y-%m-%d %H:%M:%S UTC")}"
      f.puts "**📊 Total Vulnerabilities:** #{@vulnerabilities.length}"
      f.puts
    end

    def write_executive_summary(f)
      severity_counts = count_by_severity
      critical_high = (severity_counts["CRITICAL"] || 0) + (severity_counts["HIGH"] || 0)

      f.puts "## 📋 Executive Summary"
      f.puts

      if @vulnerabilities.empty?
        f.puts "✅ **No security vulnerabilities detected.**"
      elsif critical_high == 0
        f.puts "🟡 **Low-Medium Risk**: No critical or high severity vulnerabilities found."
      elsif critical_high <= 5
        f.puts "🟠 **Moderate Risk**: #{critical_high} critical/high severity vulnerabilities require attention."
      else
        f.puts "🔴 **High Risk**: #{critical_high} critical/high severity vulnerabilities need immediate remediation."
      end

      f.puts
    end

    def write_severity_breakdown(f)
      severity_counts = count_by_severity

      f.puts "## 📊 Severity Breakdown"
      f.puts
      f.puts "| Severity | Count | Percentage |"
      f.puts "|----------|-------|------------|"

      ["CRITICAL", "HIGH", "MEDIUM", "LOW"].each do |severity|
        count = severity_counts[severity] || 0
        percentage = @vulnerabilities.empty? ? 0 : (count.to_f / @vulnerabilities.length * 100).round(1)
        config = severity_config(severity)
        f.puts "| #{config[:emoji]} **#{severity}** | #{count} | #{percentage}% |"
      end
      f.puts
    end

    def write_cvss_analysis(f)
      vulns_with_cvss = @vulnerabilities.select { |v| v[:cvss] }
      return if vulns_with_cvss.empty?

      f.puts "## 🎯 CVSS Score Analysis"
      f.puts

      scores = vulns_with_cvss.map { |v| v[:cvss][:v3_score] || v[:cvss][:v2_score] }.compact
      if scores.any?
        avg_score = (scores.sum.to_f / scores.length).round(1)
        max_score = scores.max
        f.puts "**📈 Average CVSS Score:** #{avg_score}/10.0"
        f.puts "**⚠️ Highest CVSS Score:** #{max_score}/10.0"
        f.puts

        # CVSS distribution
        cvss_ranges = {
          "Critical (9.0-10.0)" => scores.count { |s| s >= 9.0 },
          "High (7.0-8.9)" => scores.count { |s| s >= 7.0 && s < 9.0 },
          "Medium (4.0-6.9)" => scores.count { |s| s >= 4.0 && s < 7.0 },
          "Low (0.1-3.9)" => scores.count { |s| s > 0 && s < 4.0 },
        }

        f.puts "**CVSS Score Distribution:**"
        cvss_ranges.each do |range, count|
          next if count == 0
          f.puts "- #{range}: #{count} vulnerabilities"
        end
        f.puts
      end
    end

    def write_detailed_findings(f)
      f.puts "## 🔍 Detailed Findings"
      f.puts

      sorted_vulns = @vulnerabilities.sort_by do |v|
        # Sort by CVSS score first (if available), then by severity weight
        cvss_score = v[:cvss] ? (v[:cvss][:v3_score] || v[:cvss][:v2_score] || 0) : 0
        [-cvss_score, severity_config(v[:severity])[:weight]]
      end

      sorted_vulns.each_with_index do |vuln, index|
        write_vulnerability_detail(f, vuln, index + 1)
      end
    end

    def write_vulnerability_detail(f, vuln, index)
      config = severity_config(vuln[:severity])

      f.puts "### #{index}. #{config[:emoji]} #{vuln[:title]}"
      f.puts

      # Create info table
      f.puts "| Field | Value |"
      f.puts "|-------|-------|"
      f.puts "| **Severity** | #{config[:emoji]} #{vuln[:severity]} |"
      f.puts "| **CVE ID** | `#{vuln[:cve]}` |" if vuln[:cve]

      # CVSS information
      if vuln[:cvss]
        cvss = vuln[:cvss]
        if cvss[:v3_score]
          f.puts "| **CVSS v3 Score** | #{cvss[:v3_score]}/10.0 |"
          f.puts "| **CVSS v3 Vector** | `#{cvss[:v3_vector]}` |" if cvss[:v3_vector]
        elsif cvss[:v2_score]
          f.puts "| **CVSS v2 Score** | #{cvss[:v2_score]}/10.0 |"
          f.puts "| **CVSS v2 Vector** | `#{cvss[:v2_vector]}` |" if cvss[:v2_vector]
        end
      end

      f.puts "| **Package** | `#{vuln[:location]}` |"
      f.puts "| **Installed Version** | `#{vuln[:installed_version]}` |" if vuln[:installed_version]
      f.puts "| **Fixed Version** | `#{vuln[:fixed_version]}` |" if vuln[:fixed_version]
      f.puts "| **Target** | `#{vuln[:target]}` |"
      f.puts "| **Published** | #{vuln[:published_date]} |" if vuln[:published_date]
      f.puts "| **Last Modified** | #{vuln[:last_modified_date]} |" if vuln[:last_modified_date]
      f.puts

      # Description
      if vuln[:description] && !vuln[:description].empty?
        f.puts "**📝 Description:**"
        f.puts
        f.puts "> #{vuln[:description]}"
        f.puts
      end

      # References
      if vuln[:references] && vuln[:references].any?
        f.puts "**🔗 References:**"
        vuln[:references].first(5).each do |ref|
          f.puts "- #{ref}"
        end
        f.puts
      end

      f.puts "---"
      f.puts
    end

    def write_recommendations(f)
      return if @vulnerabilities.empty?

      f.puts "## 💡 Recommendations"
      f.puts

      fixable_count = @vulnerabilities.count { |v| v[:fixed_version] }

      f.puts "### Immediate Actions"
      f.puts "1. **Update Dependencies**: #{fixable_count} vulnerabilities have available fixes"
      f.puts "2. **Prioritize Critical/High**: Focus on vulnerabilities with CVSS scores ≥ 7.0"
      f.puts "3. **Review Security Policies**: Consider implementing automated vulnerability scanning"
      f.puts

      if fixable_count > 0
        f.puts "### Quick Fixes Available"
        fixable_vulns = @vulnerabilities.select { |v| v[:fixed_version] }
                                        .group_by { |v| v[:location] }

        fixable_vulns.each do |package, vulns|
          latest_fix = vulns.map { |v| v[:fixed_version] }.compact.max
          f.puts "- **#{package}**: Upgrade to version `#{latest_fix}`"
        end
        f.puts
      end
    end

    def write_scan_metadata(f)
      return if @scan_metadata.empty?

      f.puts "## 📋 Scan Metadata"
      f.puts

      @scan_metadata.each do |file, metadata|
        f.puts "**#{File.basename(file)}:**"
        f.puts "- Artifact: `#{metadata[:artifact_name]}`" if metadata[:artifact_name]
        f.puts "- Type: #{metadata[:artifact_type]}" if metadata[:artifact_type]
        f.puts "- Schema Version: #{metadata[:schema_version]}" if metadata[:schema_version]
        f.puts
      end
    end

    def generate_json_export
      output_file = File.join(@output_dir, "security-export.json")
      export_data = {
        scan_summary: {
          total_vulnerabilities: @vulnerabilities.length,
          severity_counts: count_by_severity,
          scan_date: Time.now.iso8601,
          service_name: @service_name,
        },
        vulnerabilities: @vulnerabilities,
      }

      File.open(output_file, "w") do |f|
        f.puts JSON.pretty_generate(export_data)
      end

      puts "✅ JSON export generated: #{output_file}"
    end

    def print_quick_stats
      severity_counts = count_by_severity

      puts
      puts "📊 Quick Stats:"
      puts "   🔴 Critical: #{severity_counts["CRITICAL"] || 0}"
      puts "   🟠 High:     #{severity_counts["HIGH"] || 0}"
      puts "   🟡 Medium:   #{severity_counts["MEDIUM"] || 0}"
      puts "   🔵 Low:      #{severity_counts["LOW"] || 0}"

      cvss_scores = @vulnerabilities.map { |v| v[:cvss] }.compact
      if cvss_scores.any?
        scores = cvss_scores.map { |c| c[:v3_score] || c[:v2_score] }.compact
        puts "   🎯 Avg CVSS: #{(scores.sum.to_f / scores.length).round(1)}" if scores.any?
      end
      puts
    end
  end
end
