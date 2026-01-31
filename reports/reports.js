const fs = require("fs");
const path = require("path");
const { getAIRecommendation } = require("./llmhelper");

class SecurityReportParser {
  constructor() {}

  normalizeSeverity(raw) {
    const level = (raw || "").toUpperCase();
    if (level === "ERROR") return "high";
    if (level === "WARNING") return "medium";
    if (level === "INFO") return "low";
    return "medium";
  }

  normalizeTitle(title) {
    return title.replace(/function argument `[^`]+`/, 'function argument `<VAR>`');
  }

  mergeFindings(findings) {
    const map = new Map();

    for (const f of findings) {
      const normalizedTitle = this.normalizeTitle(f.title);
      const key = `${f.rule}|${normalizedTitle}|${f.severity}`;

      const codeSnippets = [f.codeSnippets].flat().filter(Boolean);
      const lineNumbers = Array(codeSnippets.length).fill(f.lineNumbers ?? "?");
      const codeFiles = Array(codeSnippets.length).fill(f.file ?? "?");

      if (!map.has(key)) {
        map.set(key, {
          ...f,
          title: normalizedTitle,
          lineNumbers,
          codeSnippets,
          codeFiles,
          originalCount: 1,
        });
      } else {
        const existing = map.get(key);
        existing.lineNumbers.push(...lineNumbers);
        existing.codeSnippets.push(...codeSnippets);
        existing.codeFiles.push(...codeFiles);
        existing.originalCount++;
      }
    }

    return Array.from(map.values());
  }

  async enrichFindings(findings) {
    for (const finding of findings) {
      if (finding.severity === "high" || finding.severity === "medium") {
        try {
          finding.recommendation = await getAIRecommendation(finding);
        } catch (err) {
          console.warn(`Failed to fetch AI recommendation: ${err.message}`);
          finding.recommendation = "No recommendation available.";
        }
      } else {
        finding.recommendation = "No recommendation available.";
      }
    }
    return findings;
  }

  generateSummary(findings, originalFindings) {
    // Calculate counts from original findings, not merged ones
    const originalSeverityCounts = {
      high: originalFindings.filter(f => f.severity === "high").length,
      medium: originalFindings.filter(f => f.severity === "medium").length,
      low: originalFindings.filter(f => f.severity === "low").length,
    };

    return {
      total: findings.length, // Unique issues count
      high: originalSeverityCounts.high, // Original high count
      medium: originalSeverityCounts.medium, // Original medium count
      low: originalSeverityCounts.low, // Original low count
      files: new Set(findings.map(f => f.file)),
    };
  }

  displayFindingsMarkdown(findings, summary, rawTotal) {
    let report = `# Security Scan Report\n\n`;

    report += `## Summary\n`;
    report += `- Total Raw Findings: ${rawTotal}\n`;
    report += `- Unique Issues: ${summary.total}\n`;
    report += `- High: ${summary.high}\n`;
    report += `- Medium: ${summary.medium}\n`;
    report += `- Low: ${summary.low}\n`;
    report += `- Files Affected: ${summary.files.size}\n\n`;

    report += `---\n\n## Findings\n\n`;

    const sortedFindings = findings.sort((a, b) => {
      const order = { high: 3, medium: 2, low: 1 };
      return order[b.severity] - order[a.severity];
    });

    sortedFindings.forEach((finding, index) => {
      report += `### ${index + 1}. ${finding.title}\n`;
      report += `- **Severity:** ${finding.severity.toUpperCase()}\n`;
      report += `- **Rule:** ${finding.rule}\n`;

      // Show how many original findings this represents
      if (finding.originalCount > 1) {
        report += `- **Occurrences:** ${finding.originalCount}\n`;
      }

      report += `- **Line(s):** ${[...new Set(finding.codeFiles.map((f, i) => `${f}:${finding.lineNumbers[i] ?? "?"}`))].join(", ")}\n`;

      if (finding.codeSnippets?.length > 0) {
        report += `- **Code:**\n\n`;
        report += "```js\n";
        for (let i = 0; i < finding.codeSnippets.length; i++) {
          const file = finding.codeFiles[i] || finding.file || "?";
          const line = finding.lineNumbers[i] ?? "?";
          const lineLabel = `${file}:${line}`.padEnd(25);
          report += `${lineLabel} | ${finding.codeSnippets[i].trim()}\n`;
        }
        report += "```\n";
      }

      if (finding.recommendation) {
        let rec = finding.recommendation.trim();
        rec = rec.replace(/^\*{2}recommendation:\*{2}\s*/i, "");

        report += `- **Recommendation:** ${rec}\n`;
      }

      report += `\n---\n\n`;
    });

    return report;
  }

  async processReport(reportFilePath, outputFilePath = null) {
    try {
      const raw = fs.readFileSync(reportFilePath, "utf8");
      const data = JSON.parse(raw);

      const findings = data.results.map(res => ({
        severity: this.normalizeSeverity(res.extra.severity),
        rule: res.check_id,
        title: res.extra.message || res.check_id,
        file: res.path,
        lineNumbers: res.start?.line ?? "?",
        codeSnippets: res.extra?.lines || "",
        description: res.extra.metadata?.short_description || "",
        cwe: Array.isArray(res.extra.metadata?.cwe)
          ? res.extra.metadata.cwe[0]
          : res.extra.metadata?.cwe || "",
      }));

      const mergedFindings = this.mergeFindings(findings);
      const enrichedFindings = await this.enrichFindings(mergedFindings);

      const summary = this.generateSummary(enrichedFindings, findings);
      const markdownReport = this.displayFindingsMarkdown(enrichedFindings, summary, findings.length);

      if (outputFilePath) {
        fs.writeFileSync(outputFilePath, markdownReport, "utf8");
        console.log(`✅ Report written to ${outputFilePath}`);
      } else {
        console.log(markdownReport);
      }

      return { findings: enrichedFindings, summary };
    } catch (error) {
      console.error("Error processing report:", error.message);
      throw error;
    }
  }
}

if (require.main === module) {
  const reportPath = process.argv[2];
  const outputPath = process.argv[3];

  if (!reportPath) {
    console.error("Usage: node securityreports.js <report-file-path> [output-file-path]");
    process.exit(1);
  }

  const parser = new SecurityReportParser();

  (async () => {
    try {
      const result = await parser.processReport(reportPath, outputPath);
      console.log(`\n✅ Report processing completed`);
      console.log(`Found ${result.summary.total} unique issues.`);
    } catch (error) {
      console.error("❌ Failed to process report:", error.message);
      process.exit(1);
    }
  })();
}

module.exports = SecurityReportParser;