# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'claude_client'
require_relative 'changelog_analyzer'
require_relative 'gem_instrumentation_mapper'

module GemSummary
  class InstrumentationAgent
    PROMPT = <<~PROMPT
      You're reviewing a new release of a gem the New Relic Ruby Agent
      instruments. Compare the changelog against the methods we wrap.
      Don't summarize what the gem does.

      Gem: %<gem_name>s %<version>s

      Methods and classes we currently wrap:
      ```
      %<code_snippet>s
      ```

      Changelog for this release:
      ```
      %<changelog>s
      ```

      Write a Slack-formatted summary. Use *single asterisks* for bold.

      Rules:
      - Max 4 bullets, each one sentence, ≤ 35 words.
      - Every bullet MUST name a specific method, class, constant, hook,
        notification event, or config option from the changelog.
      - Prefix each bullet with its category in bold: *Breakage:*,
        *Enhancement:*, or *Deprecation:*.
      - *Breakage:* means our instrumentation actually breaks — a method we
        wrap was removed, renamed, or had its signature changed. If a method
        we wrap had internal changes but its signature is unchanged, that is
        NOT breakage; omit the bullet entirely.
      - *Enhancement:* means a public API, hook, notification, or config
        option worth wrapping that our instrumentation doesn't already cover
        (newly-added OR pre-existing). Briefly say why we'd want it. The
        changelog item can be framed as a bug fix, security fix, or
        refactor — what matters is whether the named method is something
        we'd want to wrap and currently don't.
      - Only omit a public method/hook from *Enhancement:* if our existing
        instrumentation already covers it.
      - *Deprecation:* means a method we wrap was marked deprecated.
      - If a category has no real findings, skip it. Don't pad.
      - Omit observational bullets. If a change neither breaks our wrapping
        nor exposes a wrappable API we don't already cover, leave it out.
      - Use the routine-release response ONLY when the changelog has zero
        public API/method/hook activity — i.e. only docs, tests, CI, build
        config, dependency bumps, or pure version bumps. Bug fixes and
        security fixes that touch public behavior are NOT routine. When
        you do use it, respond with exactly that single line — no
        preamble, no narrative:
        `No action needed — %<version>s is a routine release.`
      - State findings directly with action verbs ("Wrap X", "Instrument Y").
        Avoid hedging: "Consider," "may be worth," "could be useful," "may
        affect instrumentation."
      - Your response is a final answer, not a draft. Do not show your
        reasoning. Do not narrate revisions.
    PROMPT

    def self.analyze(gem_name, version)
      code_snippet = GemInstrumentationMapper.instrumentation_summary(gem_name)
      return nil if code_snippet.nil?

      changelog = ChangelogAnalyzer.fetch_changelog(gem_name)
      return nil if changelog.nil?

      prompt = format(PROMPT,
        gem_name: gem_name,
        version: version,
        code_snippet: code_snippet,
        changelog: changelog)

      ClaudeClient.new.send_message(prompt)
    rescue StandardError => e
      puts "Warning: Analysis failed for #{gem_name}: #{e.message}"
      nil
    end
  end
end
