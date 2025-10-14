# Schema-Tools - AI Log

I built schema-tools to solve a need, but also to experiment with using Cursor CLI to build a real side project.

## Quick stats

- Started the project on Sep 15
- Released the project on Oct 13 on RubyGems - https://rubygems.org/gems/schema-tools (technically released sooner, but v1.0.6 is the first good version)
- Used only Cursor CLI and occasionally Gemini for research.
- Used 202M tokens, $60 total spend (all included in my $20/mo personal subscription)
- 292 total Cursor CLI prompts - [Full Prompt Log](history_clean.csv)
- [126 commits](https://github.com/richkuz/schema-tools/commits/main/) on schema-tools, [11 commits](https://github.com/richkuz/schema-tools-sample-app/commits/main/) on schema-tools-sample-app

## Visualization of Cursor-CLI Prompt Activities

As a side-side-project I dumped 2 hours into Cursor CLI to build a tool to fetch Cursor CLI history from its SQLIte database and visualize when I did most of my prompting: https://github.com/richkuz/cursor-cli-sqlite

I only worked on this project outside of normal business hours. The graphs corroborate this, too. The bulk of AI prompts are early mornings, evenings/nights, and weekends.

![alt text](clustering_analysis.png)

![alt text](timestamp_analysis.png)


## The Evolution of Schema Tools: A Month of Rapid Development

Schema-Tools began on September 14th, 2025, with a simple initial commit containing just a LICENSE and very detailed README. The first prompt, "Read the README.md and implement everything specified in it" generated an initial working prototype. This gave me the motivation to keep going.
  
The Foundation Phase (September 14-21):
- The project started with basic infrastructure and a schema:define task
- The early phase had a complex directory structure to track major and minor revisions as separate files, with diff_output.txt files to show what changed.
- Most effort went into an initial implementation of schema:define and schema:migrate.
- No aliases in this version, everything operated on indexes.
- Built a sophisticated detector for breaking changes, with a few hours spent examining detailed breaking vs non-breaking changes. Ultimately, I didn't need the detector at all; the migration code attempts a non-breaking change and lets OpenSearch reject the change if it cannot apply it. I should have deprioritized this task sooner, but I was lured in by the ease of Cursor to build anything I asked for.
- The early version added history details as metadata on the index itself. Later I removed this feature altogether. To know exactly what schema an index is running, it's more reliable to diff the remote schema with the local schema files than to look at a metadata object.
- Project briefly renamed to "Schemurai", then renamed back to "Schema-tools". I tried to find a unique name to distinguish the history details in the index metadata section. More distraction.

The Feature Expansion Phase (September 27-October 2):
- This period focused on adding essential functionality and improving the user experience.
- Added painless script management
- Added a generic schema:seed task to populate any index with schema-compliant test data so I could start load testing.
- Added authentication support.
- Better diff capabilities, improved error handling, and more robust reindexing processes.

The Major Rewrite (October 8-10):
- The most dramatic phase was the "Version 2" release on October 8th, which represented a complete architectural overhaul.
- This massive commit (82 files changed, 1781 insertions, 6135 deletions) completely rewrote the migration system, removed the complex breaking changes detector in favor of a simpler approach, and introduced new features like rollback support, interactive mode, and configurable batch processing.
- Why: After playing with the earlier version, the directory layout that had major and minor revision changes felt too cumbersome and complex. I wanted a simple directory with "settings.json" and "mappings.json".
- Switched to using aliases to manage indexes so the application doesn't have to keep changing when adding new indexes.
- Completely rewrote rake:migrate with a 10-step approach born out of rigorous experimentation and research with OpenSearch manual testing.
- Added better diff visualization and more robust error handling during reindexing
- Drew an Excalidraw to explain the migration steps: https://excalidraw.com/#room=c24a8c892642ef7ce02f,OqZmww0-p9ppDCCBbjO-6w

Sample App (October 10-13)
- Added schema-tools-sample-app to rigorously manually test inserts/updates during each step of the migration to ensure zero data loss.
- This period was the most valuable for understanding the limitations of Elasticsearch/OpenSearch alias and reindexing capabilities.
- Rapidly iterated through many (failed) approaches until landing on a solution with the least worst tradeoffs. Heavily leaned on OpenSearch API directly to test edge cases.
- Made final adjustments by hand to the README.md.

