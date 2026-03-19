require "cgi"
require "roda"

module Gemstar
  module Web
    class App < Roda
      class << self
        def build(projects:, config_home:)
          Class.new(self) do
            opts[:projects] = projects
            opts[:config_home] = config_home
          end.freeze.app
        end
      end

      route do |r|
        @projects = self.class.opts.fetch(:projects)
        @config_home = self.class.opts.fetch(:config_home)

        r.root do
          render_page("Projects") do
            <<~HTML
              <section class="hero">
                <p class="eyebrow">Gemstar</p>
                <h1>Current projects</h1>
                <p>Config home: #{h(@config_home)}</p>
              </section>
              #{render_projects}
            HTML
          end
        end

        r.on "projects", String do |project_id|
          project = project_for(project_id)
          r.is do
            next not_found_page unless project

            render_page(project.name) do
              <<~HTML
                <p><a href="/">All projects</a></p>
                <section class="hero">
                  <p class="eyebrow">Project</p>
                  <h1>#{h(project.name)}</h1>
                  <p>#{h(project.directory)}</p>
                </section>
                #{render_project_summary(project)}
                #{render_revision_history(project)}
              HTML
            end
          end
        end
      end

      private

      def project_for(project_id)
        index = Integer(project_id, 10)
        return nil if index.negative?

        @projects[index]
      rescue ArgumentError
        nil
      end

      def render_projects
        return <<~HTML if @projects.empty?
          <section class="panel">
            <h2>No projects yet</h2>
            <p>Start the server with one or more <code>--project</code> paths.</p>
          </section>
        HTML

        items = @projects.each_with_index.map do |project, index|
          <<~HTML
            <li>
              <a href="/projects/#{index}">#{h(project.name)}</a>
              <div class="meta">#{h(project.directory)}</div>
            </li>
          HTML
        end.join

        <<~HTML
          <section class="panel">
            <h2>Projects</h2>
            <ul class="project-list">
              #{items}
            </ul>
          </section>
        HTML
      end

      def render_project_summary(project)
        <<~HTML
          <section class="panel">
            <h2>Paths</h2>
            <dl class="facts">
              <dt>Gemfile</dt>
              <dd>#{h(project.gemfile_path)}</dd>
              <dt>Gemfile.lock</dt>
              <dd>#{h(project.lockfile_path)}#{project.lockfile? ? "" : " (missing)"}</dd>
              <dt>Git root</dt>
              <dd>#{project.git_root ? h(project.git_root) : "Not in a git repository"}</dd>
            </dl>
          </section>
        HTML
      end

      def render_revision_history(project)
        revisions = project.revision_history

        return <<~HTML if revisions.empty?
          <section class="panel">
            <h2>Gemfile revisions</h2>
            <p>No git revisions found for this Gemfile or Gemfile.lock.</p>
          </section>
        HTML

        items = revisions.map do |revision|
          <<~HTML
            <li>
              <code>#{h(revision[:short_sha])}</code>
              <strong>#{h(revision[:subject])}</strong>
              <div class="meta">#{h(revision[:authored_at].iso8601)}</div>
            </li>
          HTML
        end.join

        <<~HTML
          <section class="panel">
            <h2>Gemfile revisions</h2>
            <ol class="revision-list">
              #{items}
            </ol>
          </section>
        HTML
      end

      def render_page(title)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>Gemstar: #{h(title)}</title>
              <style>
                :root {
                  color-scheme: light;
                  --bg: #f5efe3;
                  --paper: #fffaf2;
                  --ink: #1f1a17;
                  --muted: #6a5e55;
                  --accent: #b4482d;
                  --line: #ddcfbf;
                }

                * { box-sizing: border-box; }
                body {
                  margin: 0;
                  font-family: "Iowan Old Style", "Palatino Linotype", serif;
                  background:
                    radial-gradient(circle at top left, rgba(180, 72, 45, 0.14), transparent 26rem),
                    linear-gradient(180deg, #f8f1e7 0%, var(--bg) 100%);
                  color: var(--ink);
                }
                main {
                  max-width: 64rem;
                  margin: 0 auto;
                  padding: 2rem 1rem 4rem;
                }
                a { color: var(--accent); }
                code {
                  font-family: "SFMono-Regular", "Cascadia Code", monospace;
                  font-size: 0.95em;
                }
                .hero {
                  padding: 1.5rem 0 1rem;
                }
                .eyebrow {
                  margin: 0;
                  color: var(--accent);
                  text-transform: uppercase;
                  letter-spacing: 0.08em;
                  font-size: 0.78rem;
                }
                h1, h2 {
                  margin: 0 0 0.75rem;
                  line-height: 1.1;
                }
                .panel {
                  background: color-mix(in srgb, var(--paper) 88%, white);
                  border: 1px solid var(--line);
                  border-radius: 1rem;
                  padding: 1.25rem;
                  margin-top: 1rem;
                  box-shadow: 0 0.75rem 2rem rgba(80, 55, 36, 0.08);
                }
                .project-list,
                .revision-list {
                  margin: 0;
                  padding-left: 1.25rem;
                }
                .project-list li,
                .revision-list li {
                  padding: 0.45rem 0;
                }
                .meta {
                  color: var(--muted);
                  font-size: 0.95rem;
                  margin-top: 0.2rem;
                }
                .facts {
                  display: grid;
                  grid-template-columns: max-content 1fr;
                  gap: 0.5rem 1rem;
                  margin: 0;
                }
                .facts dt {
                  font-weight: 700;
                }
                .facts dd {
                  margin: 0;
                  color: var(--muted);
                  overflow-wrap: anywhere;
                }
              </style>
            </head>
            <body>
              <main>
                #{yield}
              </main>
            </body>
          </html>
        HTML
      end

      def not_found_page
        response.status = 404
        render_page("Not found") do
          <<~HTML
            <section class="panel">
              <h1>Project not found</h1>
              <p><a href="/">Back to projects</a></p>
            </section>
          HTML
        end
      end

      def h(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end
