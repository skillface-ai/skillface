import Foundation

/// What an app's `interface.html` is given and held to. The page is written by the builder from
/// a skill off the internet and it sees the user's memory, so it loads nothing and goes nowhere:
/// the policy here refuses every request, and `InterfaceView` refuses every navigation.
///
/// What a page can call is a contract: change `bridge` or `css` and `BuilderSkills.interface`,
/// which is what the builder reads, changes with it.
package enum Interface {
    /// What a page shows: the state `skillface` hands it.
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

        /// As the argument `__skillface` takes.
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

    /// Skillface's own look, which every app starts from, so an app belongs in the room it's in:
    /// always dark, a serif for what's said large, a monospace for small labels, one accent.
    /// `Theme` has the same colours for the app around the page.
    static let css = """
        :root { color-scheme: dark; --text: #f2f3f5; --secondary: #a3a8b3; --tertiary: #6d7380; --bg: #15171b; \
        --surface: #22252b; --line: #2a2e36; --accent: #ff6a47; --on-accent: #0c0d10; --radius: 14px; \
        --display: ui-serif, "New York", "Iowan Old Style", Georgia, serif; \
        --mono: ui-monospace, "SF Mono", Menlo, monospace }
        * { box-sizing: border-box }
        html, body { height: 100%; margin: 0 }
        body { font: 15px/1.5 -apple-system, system-ui, sans-serif; color: var(--text); background: var(--bg); \
        -webkit-font-smoothing: antialiased }
        h1, h2, h3 { font-family: var(--display); font-weight: 400; letter-spacing: -0.015em }
        code, pre { font: 13px/1.5 var(--mono) }
        pre { background: var(--surface); padding: 12px 14px; border-radius: 8px; overflow-x: auto }
        button, input, textarea, select { font: inherit; color: inherit }
        ::selection { background: rgba(255, 106, 71, 0.35) }
        ::placeholder { color: var(--tertiary) }
        """

    /// `window.skillface`, run before the page's own scripts. `__skillface(state)` is how the app hands
    /// it a new state; `skillface.send` is the page's one way back.
    package static let bridge = #"""
        (() => {
          const state = { app: { name: "" }, session: { title: "" }, messages: [], memory: {}, busy: false, status: "", preview: false };
          const listeners = [];
          const report = (error) => window.webkit.messageHandlers.skillface.postMessage({ error: String(error) });
          const fire = () => listeners.forEach((fn) => { try { fn(window.skillface) } catch (error) { report(error) } });
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
          window.skillface = {
            get app() { return state.app }, get session() { return state.session },
            get messages() { return state.messages }, get memory() { return state.memory },
            get busy() { return state.busy }, get status() { return state.status }, get preview() { return state.preview },
            json(name) { try { return JSON.parse(state.memory[name]) } catch { return null } },
            send(text) {
              text = String(text ?? "").trim();
              if (!text || state.busy) return;
              // A preview has no agent: what's sent is shown, so the design can be tried.
              if (state.preview) { state.messages = [...state.messages, { role: "user", text }]; fire() }
              else window.webkit.messageHandlers.skillface.postMessage(text);
            },
            onChange(fn) { listeners.push(fn); try { fn(window.skillface) } catch (error) { report(error) } },
            html, escape,
          };
          // Skillface was called Yokan, and Yonka before that, and the pages built then call
          // `yokan` or `yonka`: the same object, so they go on working.
          window.yokan = window.yonka = window.skillface;
          window.__skillface = (next) => { Object.assign(state, next); fire() };
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
          .message :is(h1, h2, h3, h4) { font-size: 19px; margin: 18px 0 6px }
          .empty { height: 100%; display: grid; place-content: center; text-align: center; color: var(--secondary) }
          .empty h1 { font-size: 40px; letter-spacing: -0.025em; color: var(--text); margin: 0 0 6px }
          footer { padding: 4px 28px 24px }
          #status { height: 22px; font: 11.5px var(--mono); color: var(--secondary) }
          #status.busy::before { content: ""; display: inline-block; width: 6px; height: 6px; margin-right: 8px; border-radius: 50%; background: var(--accent); animation: pulse 1.2s ease-in-out infinite; vertical-align: middle }
          textarea { display: block; width: 100%; resize: none; max-height: 180px; padding: 11px 18px; border: 1px solid var(--line); border-radius: 22px; background: transparent; outline: none; transition: border-color 0.2s }
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

          skillface.onChange(() => {
            const messages = skillface.messages;
            log.classList.toggle("empty", !messages.length);
            if (!messages.length) {
              log.innerHTML = `<h1>${skillface.escape(skillface.app.name)}</h1><div>Say something to begin.</div>`;
              drawn = 0;
            } else {
              // Only the last message changes while an answer streams: the rest stay as drawn.
              if (!drawn) log.innerHTML = "";
              const kept = Math.max(drawn - 1, 0);
              while (log.children.length > kept) log.lastChild.remove();
              messages.slice(kept).forEach((message, index) => {
                const row = document.createElement("div");
                row.className = "message " + message.role + (kept + index >= drawn ? " new" : "");
                row.innerHTML = "<div>" + (message.role === "user" ? skillface.escape(message.text) : skillface.html(message.text)) + "</div>";
                log.append(row);
              });
              drawn = messages.length;
              main.scrollTop = main.scrollHeight;
            }
            status.textContent = skillface.busy ? (skillface.status || "Thinking") : "";
            status.classList.toggle("busy", skillface.busy);
          });

          box.addEventListener("input", () => { box.style.height = "auto"; box.style.height = box.scrollHeight + 2 + "px" });
          box.addEventListener("keydown", (event) => {
            if (event.key !== "Enter" || event.shiftKey || event.isComposing || skillface.busy || !box.value.trim()) return;
            event.preventDefault();
            skillface.send(box.value);
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
