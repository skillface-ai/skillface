import Foundation

/// What an app's `interface.html` is given and held to. The page is written by the builder from
/// a skill off the internet and it sees the user's memory, so it loads nothing and goes nowhere:
/// the policy here refuses every request, and `InterfaceView` refuses every navigation.
///
/// What a page can call is a contract: change `bridge` or `css` and `BuilderSkills.interface`,
/// which is what the builder reads, changes with it.
package enum Interface {
    /// What a page shows: the state `yonka` hands it.
    package struct State: Equatable, Sendable {
        package let app: String
        package let session: String
        package let messages: [Session.Message]
        package let memory: [TextFile]
        package let busy: Bool
        package let status: String
        package let preview: Bool

        package init(
            app: String, session: String = "", messages: [Session.Message] = [], memory: [TextFile] = [],
            busy: Bool = false, status: String = "", preview: Bool = false
        ) {
            (self.app, self.session, self.messages, self.memory) = (app, session, messages, memory)
            (self.busy, self.status, self.preview) = (busy, status, preview)
        }

        /// As the argument `__yonka` takes.
        package var json: String {
            let object: [String: Any] = [
                "app": ["name": app], "session": ["title": session],
                "messages": messages.map { ["role": $0.role.rawValue, "text": $0.text] },
                "memory": Dictionary(memory.map { ($0.name, $0.text) }) { $1 },
                "busy": busy, "status": status, "preview": preview,
            ]
            return String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), as: UTF8.self)
        }
    }

    /// The design's preview: `demo.json`'s memory and messages. The builder writes it, so
    /// whatever it gets wrong is left out, and a memory given as JSON rather than text is its text.
    package static func preview(of app: String, demo: String) -> State {
        let object = (try? JSONSerialization.jsonObject(with: Data(demo.utf8))) as? [String: Any] ?? [:]
        let memory = (object["memory"] as? [String: Any] ?? [:]).compactMap { name, value -> TextFile? in
            if let text = value as? String { return TextFile(name: name, text: text) }
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            else { return nil }
            return TextFile(name: name, text: String(decoding: data, as: UTF8.self))
        }
        let messages = (object["messages"] as? [[String: Any]] ?? []).compactMap { message -> Session.Message? in
            guard let role = (message["role"] as? String).flatMap(Session.Role.init), let text = message["text"] as? String else { return nil }
            return Session.Message(role: role, text: text)
        }
        return State(app: app, session: "Preview", messages: messages, memory: memory.sorted { $0.name < $1.name }, preview: true)
    }

    /// The page as the web view loads it: the policy and the base CSS, then the app's own HTML.
    /// A doctype first keeps it out of quirks mode; the page's own, coming second, is ignored.
    package static func page(_ html: String) -> String {
        "<!doctype html><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><style>\(css)</style>\n\(html)"
    }

    /// Inline styles and scripts, and images, fonts and sound only as data. Nothing is fetched,
    /// posted or framed.
    static let policy = "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; form-action 'none'; base-uri 'none'"

    static let css = """
        :root { color-scheme: light dark; --text: #1d1d1f; --secondary: #6e6e73; --tertiary: #aeaeb2; --bg: #ffffff; \
        --surface: #f5f5f7; --line: #e3e3e8; --accent: #0071e3; --radius: 12px }
        @media (prefers-color-scheme: dark) { :root { --text: #f5f5f7; --secondary: #a1a1a6; --tertiary: #636366; \
        --bg: #1e1e1e; --surface: #2c2c2e; --line: #3a3a3c; --accent: #2997ff } }
        * { box-sizing: border-box }
        html, body { height: 100%; margin: 0 }
        body { font: 15px/1.5 -apple-system, system-ui, sans-serif; color: var(--text); background: var(--bg); \
        -webkit-font-smoothing: antialiased }
        code, pre { font: 13px/1.5 ui-monospace, "SF Mono", Menlo, monospace }
        pre { background: var(--surface); padding: 12px 14px; border-radius: 8px; overflow-x: auto }
        button, input, textarea, select { font: inherit; color: inherit }
        """

    /// `window.yonka`, run before the page's own scripts. `__yonka(state)` is how the app hands
    /// it a new state; `yonka.send` is the page's one way back.
    package static let bridge = #"""
        (() => {
          const state = { app: { name: "" }, session: { title: "" }, messages: [], memory: {}, busy: false, status: "", preview: false };
          const listeners = [];
          const report = (error) => window.webkit.messageHandlers.yonka.postMessage({ error: String(error) });
          const fire = () => listeners.forEach((fn) => { try { fn(window.yonka) } catch (error) { report(error) } });
          const escape = (text) => String(text ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
          const inline = (text) => escape(text)
            .replace(/`([^`]+)`/g, "<code>$1</code>")
            .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
            .replace(/(^|[^*\w])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>");
          // ponytail: paragraphs, headings, lists, code, bold and italic, which is what an agent
          // writes in conversation. Tables and links come out as their text.
          const html = (markdown) => {
            const out = [];
            let list = null, code = null, lines = [];
            const close = () => {
              if (lines.length) out.push("<p>" + lines.map(inline).join("<br>") + "</p>");
              if (list) out.push("</" + list + ">");
              lines = []; list = null;
            };
            for (const line of String(markdown ?? "").split("\n")) {
              const fence = /^\s*```/.test(line);
              if (code) {
                if (fence) { out.push("<pre><code>" + escape(code.join("\n")) + "</code></pre>"); code = null } else code.push(line);
                continue;
              }
              const heading = /^(#{1,4})\s+(.*)/.exec(line), item = /^\s*([-*]|\d+\.)\s+(.*)/.exec(line);
              if (fence) { close(); code = [] }
              else if (heading) { close(); out.push(`<h${heading[1].length}>${inline(heading[2])}</h${heading[1].length}>`) }
              else if (item) {
                const kind = /\d/.test(item[1]) ? "ol" : "ul";
                if (list !== kind) { close(); out.push("<" + kind + ">"); list = kind }
                out.push("<li>" + inline(item[2]) + "</li>");
              }
              else if (!line.trim()) close();
              else { if (list) close(); lines.push(line) }
            }
            if (code) out.push("<pre><code>" + escape(code.join("\n")) + "</code></pre>");
            close();
            return out.join("");
          };
          window.yonka = {
            get app() { return state.app }, get session() { return state.session },
            get messages() { return state.messages }, get memory() { return state.memory },
            get busy() { return state.busy }, get status() { return state.status }, get preview() { return state.preview },
            json(name) { try { return JSON.parse(state.memory[name]) } catch { return null } },
            send(text) {
              text = String(text ?? "").trim();
              if (!text || state.busy) return;
              // A preview has no agent: what's sent is shown, so the design can be tried.
              if (state.preview) { state.messages = [...state.messages, { role: "user", text }]; fire() }
              else window.webkit.messageHandlers.yonka.postMessage(text);
            },
            onChange(fn) { listeners.push(fn); try { fn(window.yonka) } catch (error) { report(error) } },
            html, escape,
          };
          window.__yonka = (next) => { Object.assign(state, next); fire() };
          // A page that breaks says so, rather than sitting there blank.
          window.addEventListener("error", (event) => report(event.message));
        })();
        """#

    /// What a new app has until the builder designs its own: a plain conversation, and the
    /// example the builder's skill points at.
    package static let starter = #"""
        <!doctype html>
        <meta charset="utf-8">
        <style>
          body { display: flex; flex-direction: column }
          main { flex: 1; overflow-y: auto; padding: 48px 28px 8px }
          .column { max-width: 680px; margin: 0 auto }
          .message { margin-bottom: 24px }
          .message.new { animation: arrive 0.2s ease-out }
          .message.user { display: flex; justify-content: flex-end }
          .message.user div { background: var(--surface); padding: 9px 15px; border-radius: 18px; max-width: 80%; white-space: pre-wrap }
          .message :is(p, ul, ol, pre) { margin: 0 0 10px }
          .message :last-child { margin-bottom: 0 }
          .message :is(h1, h2, h3, h4) { font-size: 15px; font-weight: 600; margin: 18px 0 6px }
          .empty { height: 100%; display: grid; place-content: center; text-align: center; color: var(--secondary) }
          .empty h1 { font-size: 28px; font-weight: 600; letter-spacing: -0.02em; color: var(--text); margin: 0 0 4px }
          footer { padding: 4px 28px 24px }
          #status { height: 22px; font-size: 13px; color: var(--secondary) }
          #status.busy::before { content: ""; display: inline-block; width: 6px; height: 6px; margin-right: 8px; border-radius: 50%; background: var(--accent); animation: pulse 1.2s ease-in-out infinite; vertical-align: middle }
          textarea { display: block; width: 100%; resize: none; max-height: 180px; padding: 11px 18px; border: 1px solid var(--line); border-radius: 22px; background: var(--bg); outline: none; transition: border-color 0.2s }
          textarea:focus { border-color: var(--accent) }
          @keyframes arrive { from { opacity: 0; transform: translateY(4px) } }
          @keyframes pulse { 50% { opacity: 0.25 } }
        </style>
        <main><div class="column" id="log"></div></main>
        <footer><div class="column">
          <div id="status"></div>
          <textarea id="box" rows="1" placeholder="Message" autofocus></textarea>
        </div></footer>
        <script>
        // In a block: WebKit refuses a top-level const named like something of window's, as `status` is.
        {
          const main = document.querySelector("main"), log = document.getElementById("log");
          const status = document.getElementById("status"), box = document.getElementById("box");
          let drawn = 0;

          yonka.onChange(() => {
            const messages = yonka.messages;
            log.classList.toggle("empty", !messages.length);
            if (!messages.length) {
              log.innerHTML = `<h1>${yonka.escape(yonka.app.name)}</h1><div>Say something to begin.</div>`;
              drawn = 0;
            } else {
              // Only the last message changes while an answer streams: the rest stay as drawn.
              if (!drawn) log.innerHTML = "";
              const kept = Math.max(drawn - 1, 0);
              while (log.children.length > kept) log.lastChild.remove();
              messages.slice(kept).forEach((message, index) => {
                const row = document.createElement("div");
                row.className = "message " + message.role + (kept + index >= drawn ? " new" : "");
                row.innerHTML = "<div>" + (message.role === "user" ? yonka.escape(message.text) : yonka.html(message.text)) + "</div>";
                log.append(row);
              });
              drawn = messages.length;
              main.scrollTop = main.scrollHeight;
            }
            status.textContent = yonka.busy ? (yonka.status || "Thinking") : "";
            status.classList.toggle("busy", yonka.busy);
          });

          box.addEventListener("input", () => { box.style.height = "auto"; box.style.height = box.scrollHeight + 2 + "px" });
          box.addEventListener("keydown", (event) => {
            if (event.key !== "Enter" || event.shiftKey || event.isComposing || yonka.busy || !box.value.trim()) return;
            event.preventDefault();
            yonka.send(box.value);
            box.value = "";
            box.style.height = "auto";
          });
        }
        </script>
        """#

    package static let starterDemo = #"""
        {
          "memory": {},
          "messages": [
            { "role": "user", "text": "Let's begin." },
            { "role": "assistant", "text": "This is a preview. Once the design is settled, this is where the conversation will be." }
          ]
        }
        """#
}
