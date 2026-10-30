// A Mac desktop made of DOM: a Dock that magnifies, one window at a time, three disguised VS Codes,
// the Code-o-ween manager, and a browser showing the page this used to be.
// Nothing here talks to a server, and nothing installs anything. It is a costume.
(() => {
  "use strict";

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const isPhone = () => matchMedia("(max-width: 720px)").matches;

  // createElement with less typing: el("span.title", { text: "hi" }, [children])
  const el = (spec, props = {}, children = []) => {
    const [tag, ...classes] = spec.split(".");
    const node = document.createElement(tag || "div");
    if (classes.length) node.className = classes.join(" ");
    for (const [key, value] of Object.entries(props)) {
      if (key === "text") node.textContent = value;
      else if (key === "dataset") Object.assign(node.dataset, value);
      else if (key === "style") for (const [prop, v] of Object.entries(value)) node.style.setProperty(prop, v);
      else if (key.startsWith("aria-") || key === "role" || key === "hidden" && value === "") node.setAttribute(key, value);
      else node[key] = value;
    }
    for (const child of [].concat(children)) {
      if (child == null) continue;
      node.append(typeof child === "string" ? document.createTextNode(child) : child);
    }
    return node;
  };

  // Same rule the real tool uses: dark text on light tints, white on dark ones.
  const foregroundFor = (hex) => {
    const n = parseInt(hex.slice(1), 16);
    const channel = (v) => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
    const l = 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255);
    return (1.05 / (l + 0.05)) >= ((l + 0.05) / 0.0585) ? "#FFFFFF" : "#1F1F1F";
  };

  const slugify = (name) => name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "disguise";

  // The 15 presets of the real app, in the same order.
  const PRESETS = [
    ["black", "#212121"], ["navy", "#1A237E"], ["magenta", "#AD1457"], ["indigo", "#3F51B5"], ["brown", "#795548"],
    ["slate", "#546E7A"], ["purple", "#7E57C2"], ["lime", "#4F7D2A"], ["yellow", "#946A00"], ["orange", "#BF4F00"],
    ["green", "#1E8255"], ["teal", "#007F88"], ["red", "#D13C3C"], ["blue", "#2276D2"], ["pink", "#D33682"],
  ];
  const presetName = (hex) => (PRESETS.find(([, h]) => h.toUpperCase() === hex.toUpperCase()) || [hex.toUpperCase()])[0];

  // ───────────────────────────── The three costumes ─────────────────────────────
  // Code lines are arrays of [tokenClass, text] so no markup is ever built from strings.
  const DISGUISES = [
    {
      id: "main-project", name: "Main Project", label: "Main Project", emoji: "🎃", color: "#BF4F00",
      folder: "~/code/main-project", repo: "main-project", branch: "main*", lang: "TypeScript", pos: "Ln 6, Col 44",
      file: "standup.ts",
      tree: [
        ["dir", ".github", 0], ["dir open", "src", 0],
        ["file", "cauldron.ts", 1, "TS"], ["file active", "standup.ts", 1, "TS"], ["file", "potions.ts", 1, "TS"],
        ["dir", "tests", 0], ["file", "package.json", 0, "{}"], ["file", "README.md", 0, "M↓"],
      ],
      tabs: ["standup.ts", "cauldron.ts"],
      code: [
        [["c", "// Main Project. The one that pays the rent. Allegedly."]],
        [["k", "import"], ["", " { "], ["v", "brew"], ["", " } "], ["k", "from"], ["", " "], ["s", "\"./cauldron\""], ["", ";"]],
        [],
        [["k", "export"], ["", " "], ["k", "async function"], ["", " "], ["f", "standup"], ["", "("], ["v", "today"], ["", ": "], ["t", "Date"], ["", ") {"]],
        [["", "  "], ["d", "const"], ["", " "], ["v", "coffee"], ["", " = "], ["k", "await"], ["", " "], ["f", "brew"], ["", "("], ["s", "\"coffee\""], ["", ", { "], ["v", "strength"], ["", ": "], ["s", "\"double\""], ["", " });"]],
        [["", "  "], ["k", "return"], ["", " {"]],
        [["", "    "], ["v", "yesterday"], ["", ": ["], ["s", "\"fixed the thing\""], ["", "],"]],
        [["", "    "], ["v", "today"], ["", ": ["], ["s", "\"break a different thing\""], ["", "],"]],
        [["", "    "], ["v", "blockers"], ["", ": "], ["v", "coffee"], ["", "."], ["v", "isEmpty"], ["", " ? ["], ["s", "\"see above\""], ["", "] : [],"]],
        [["", "  };"]],
        [["", "}"]],
      ],
      terminal: [
        [["prompt", "$ "], ["", "code-o-ween create \"Main Project\" --emoji 🎃 --color orange --folder ~/code/main-project"]],
        [["dim", "Created ~/Applications/Code-o-ween/VS Code - Main Project.app"]],
        [["prompt", "$ "], ["", "git status"]],
        [["dim", "nothing to commit, working tree clean   # a lie, but a comforting one"]],
      ],
    },
    {
      id: "side-project-a", name: "Side Project A", label: "Side Project A", emoji: "👻", color: "#7E57C2",
      folder: "~/code/haunted-todo", repo: "haunted-todo", branch: "feature/actually-finish-it", lang: "TypeScript JSX", pos: "Ln 11, Col 3",
      file: "HauntedTodo.tsx",
      tree: [
        ["dir", "node_modules", 0], ["dim file", "(999 folders, 4 of them used)", 1, "…"], ["dir", "public", 0], ["dir open", "src", 0],
        ["file active", "HauntedTodo.tsx", 1, "⚛"], ["file", "ghosts.ts", 1, "TS"], ["file", "index.tsx", 1, "⚛"],
        ["file", "package.json", 0, "{}"], ["file", "TODO.md", 0, "M↓"],
      ],
      tabs: ["HauntedTodo.tsx", "TODO.md"],
      code: [
        [["c", "// Side Project A: a todo app. Every developer has one. This one has ghosts."]],
        [["k", "import"], ["", " { "], ["v", "useState"], ["", " } "], ["k", "from"], ["", " "], ["s", "\"react\""], ["", ";"]],
        [],
        [["k", "export"], ["", " "], ["k", "function"], ["", " "], ["f", "HauntedTodo"], ["", "() {"]],
        [["", "  "], ["d", "const"], ["", " ["], ["v", "todos"], ["", ", "], ["v", "setTodos"], ["", "] = "], ["f", "useState"], ["", "<"], ["t", "Todo"], ["", "[]>(["]],
        [["", "    { "], ["v", "text"], ["", ": "], ["s", "\"finish Side Project A\""], ["", ", "], ["v", "done"], ["", ": "], ["d", "false"], ["", ", "], ["v", "since"], ["", ": "], ["n", "2019"], ["", " },"]],
        [["", "    { "], ["v", "text"], ["", ": "], ["s", "\"pick a name\""], ["", ", "], ["v", "done"], ["", ": "], ["d", "false"], ["", ", "], ["v", "since"], ["", ": "], ["n", "2019"], ["", " },"]],
        [["", "  ]);"]],
        [],
        [["", "  "], ["c", "// TODO: deleted todos come back at midnight. Ship it as a feature."]],
        [["", "  "], ["k", "return"], ["", " <"], ["t", "List"], ["", " "], ["v", "items"], ["", "={"], ["v", "todos"], ["", "} "], ["v", "onToggle"], ["", "={"], ["v", "haunt"], ["", "} />;"]],
        [["", "}"]],
      ],
      terminal: [
        [["prompt", "$ "], ["", "npm run dev"]],
        [["dim", "> haunted-todo@0.0.1 dev"]],
        [["", "  ➜  Local:   http://localhost:5173/   "], ["dim", "(running since 2019)"]],
      ],
    },
    {
      id: "side-project-b", name: "Side Project B", label: "Side Project B (has a domain)", emoji: "🧛", color: "#D13C3C",
      folder: "~/code/spooky.dev", repo: "spooky.dev", branch: "main", lang: "NGINX", pos: "Ln 10, Col 9",
      file: "nginx.conf",
      tree: [
        ["dir open", "deploy", 0], ["file active", "nginx.conf", 1, "⚙"], ["file", "dns.tf", 1, "tf"],
        ["file", "index.html", 0, "<>"], ["file", "LICENSE", 0, "§"], ["file", "pitch-deck.key", 0, "▶"], ["file", "README.md", 0, "M↓"],
      ],
      tabs: ["nginx.conf", "dns.tf"],
      code: [
        [["c", "# Side Project B. It has a domain, which makes it a company."]],
        [["d", "server"], ["", " {"]],
        [["", "    "], ["v", "listen"], ["", "       "], ["n", "443"], ["", " ssl http2;"]],
        [["", "    "], ["v", "server_name"], ["", "  spooky.dev www.spooky.dev;"]],
        [],
        [["", "    "], ["c", "# renew before the certificate turns back into a pumpkin at midnight"]],
        [["", "    "], ["v", "ssl_certificate"], ["", "      /etc/letsencrypt/live/spooky.dev/fullchain.pem;"]],
        [],
        [["", "    "], ["d", "location"], ["", " / {"]],
        [["", "        "], ["v", "return"], ["", " "], ["n", "200"], ["", " "], ["s", "\"coming soon 🦇\""], ["", ";"]],
        [["", "    }"]],
        [["", "}"]],
      ],
      terminal: [
        [["prompt", "$ "], ["", "whois spooky.dev | grep -i expir"]],
        [["dim", "Registry Expiry Date: 2027-10-31T00:00:00Z"]],
        [["prompt", "$ "], ["", "# renewed. that's the whole roadmap."]],
      ],
    },
  ];

  const disguises = new Map(DISGUISES.map((d) => [d.id, d]));

  // ───────────────────────────── Window manager ─────────────────────────────
  const windowsLayer = $("#windows");
  const menubarApp = $("#menubar-app");
  let zTop = 10;

  const windowsFor = (app) => $$(`.window[data-app="${app}"]`, windowsLayer);
  const dockItemFor = (app) => $(`.dock-item[data-app="${app}"]`);

  const focusWindow = (win) => {
    $$(".window.focused").forEach((w) => w.classList.remove("focused"));
    win.classList.add("focused");
    win.style.zIndex = String(++zTop);
    menubarApp.textContent = win.dataset.title;
  };

  // Windows don't move: each one sits centered on the desktop, re-centered every time it opens.
  const placeWindow = (win, width, height) => {
    const area = windowsLayer.getBoundingClientRect();
    const w = Math.min(width, area.width - 24);
    const h = Math.min(height, area.height - 24);
    win.style.width = `${w}px`;
    win.style.height = `${h}px`;
    win.style.left = `${Math.max(12, (area.width - w) / 2)}px`;
    win.style.top = `${Math.max(12, (area.height - h) / 2)}px`;
  };

  // While the browser is the window on screen, its page scrolls with the document instead of inside a box.
  const syncPageScroll = () => {
    const browserWin = $(".window.browser", windowsLayer);
    document.documentElement.classList.toggle("page-scroll", !!browserWin && !browserWin.hidden);
  };

  // One window at a time: the others step aside, still running, like apps hidden with ⌘H.
  const hideOthers = (win) => {
    for (const other of $$(".window:not([hidden])", windowsLayer)) {
      if (other === win) continue;
      other.hidden = true;
      other.dataset.minimized = "true";
      other.classList.remove("focused", "minimizing");
      updateRunning(other.dataset.app);
    }
  };

  const updateRunning = (app) => {
    const item = dockItemFor(app);
    if (!item) return;
    const running = windowsFor(app).some((w) => !w.hidden || w.dataset.minimized === "true");
    item.classList.toggle("running", running);
  };

  const showWindow = (win) => {
    const app = win.dataset.app;
    hideOthers(win);
    // Switch layouts before measuring, so a window opened from the scrolled browser is sized for the desktop.
    document.documentElement.classList.toggle("page-scroll", win.classList.contains("browser"));
    if (win.hidden) {
      if (!win.classList.contains("maximized")) placeWindow(win, Number(win.dataset.width) || 760, Number(win.dataset.height) || 500);
      win.hidden = false;
      window.scrollTo(0, 0);
      win.dataset.minimized = "false";
      win.classList.remove("minimizing");
      if (!reducedMotion) {
        win.classList.add("opening");
        win.addEventListener("animationend", () => win.classList.remove("opening"), { once: true });
      }
    }
    focusWindow(win);
    updateRunning(app);
  };

  const closeWindow = (win) => {
    win.hidden = true;
    win.dataset.minimized = "false";
    win.classList.remove("focused", "maximized");
    updateRunning(win.dataset.app);
    syncPageScroll();
    menubarApp.textContent = "Haunter";
  };

  const minimizeWindow = (win) => {
    const finish = () => {
      win.hidden = true;
      win.classList.remove("minimizing", "focused");
      win.dataset.minimized = "true";
      updateRunning(win.dataset.app);
      syncPageScroll();
      menubarApp.textContent = "Haunter";
    };
    if (reducedMotion) return finish();
    win.classList.add("minimizing");
    win.addEventListener("transitionend", finish, { once: true });
  };

  const zoomWindow = (win) => {
    if (win.classList.contains("maximized")) {
      win.classList.remove("maximized");
      Object.assign(win.style, win.dataset.restore ? JSON.parse(win.dataset.restore) : {});
    } else {
      win.dataset.restore = JSON.stringify({ left: win.style.left, top: win.style.top, width: win.style.width, height: win.style.height });
      win.classList.add("maximized");
      Object.assign(win.style, { left: "0px", top: "0px", width: "100%", height: "100%" });
    }
  };

  const wireWindow = (win) => {
    $(".titlebar", win).addEventListener("dblclick", (event) => { if (!event.target.closest("button")) zoomWindow(win); });
    win.addEventListener("pointerdown", () => { if (!win.classList.contains("focused")) focusWindow(win); });
    $(".tl.close", win).addEventListener("click", () => closeWindow(win));
    $(".tl.min", win).addEventListener("click", () => minimizeWindow(win));
    $(".tl.zoom", win).addEventListener("click", () => zoomWindow(win));
  };

  // ───────────────────────────── VS Code windows ─────────────────────────────
  const codeLine = (tokens) => el("div.ln", {}, tokens.length ? tokens.map(([cls, text]) => el(cls ? `span.${cls}` : "span", { text })) : [el("span", { text: " " })]);

  const buildVSCode = (d) => {
    const fg = foregroundFor(d.color);
    const title = `${d.emoji} ${d.file} — ${d.repo} — ${d.name}`;
    const win = el("section.window.vscode", {
      "aria-label": title,
      dataset: { app: `disguise:${d.id}`, title: d.name, width: "820", height: "520" },
      style: { "--tint": d.color, "--tint-fg": fg },
    });
    win.hidden = true;

    const lights = el("span.lights", {}, [
      el("button.tl.close", { type: "button", "aria-label": "Close" }), el("button.tl.min", { type: "button", "aria-label": "Minimize" }), el("button.tl.zoom", { type: "button", "aria-label": "Zoom" }),
    ]);
    win.append(el("div.titlebar", {}, [lights, el("span.title", { text: title })]));

    const activity = el("div.activity", { "aria-hidden": "true" }, ["⧉", "⌕", "⑂", "▷", "⊞"].map((glyph, i) => el(i === 0 ? "i.active" : "i", { text: glyph })));

    const tree = el("ul.tree", {}, d.tree.map(([cls, name, depth, glyph]) => {
      const li = el(`li.${cls.split(" ").join(".")}`, { text: name, style: { "--depth": String(depth) } });
      if (glyph) li.dataset.glyph = glyph;
      return li;
    }));
    const sidebar = el("div.sidebar", { "aria-hidden": "true" }, [
      el("div.sidebar-head", { text: "Explorer" }),
      el("div.sidebar-root", { text: `⌄ ${d.repo.toUpperCase()}` }),
      tree,
    ]);

    const tabs = el("div.tabs", { "aria-hidden": "true" }, d.tabs.map((name, i) => el(i === 0 ? "span.active" : "span", { text: name })));
    const code = el("pre.code", { "aria-label": `${d.file} in ${d.repo}` }, d.code.map(codeLine));
    const terminal = el("div.terminal", { "aria-hidden": "true" }, [
      el("div.terminal-tabs", {}, [el("span", { text: "Problems" }), el("span", { text: "Output" }), el("span.active", { text: "Terminal" })]),
      el("pre", {}, d.terminal.flatMap((tokens, i) => [
        ...tokens.map(([cls, text]) => el(cls ? `span.${cls}` : "span", { text })),
        i === d.terminal.length - 1 ? el("span", {}, [" ", el("span.cursor")]) : "\n",
      ])),
    ]);
    const editorCol = el("div.editor-col", {}, [tabs, code, terminal]);

    win.append(el("div.vscode-body", {}, [activity, sidebar, editorCol]));
    win.append(el("div.statusbar", { "aria-hidden": "true" }, [
      el("span.remote", { text: "⧉" }),
      el("span", { text: `⎇ ${d.branch}` }), el("span", { text: "⟳" }), el("span", { text: "⊗ 0  ⚠ 0" }),
      el("span.spacer"),
      el("span", { text: d.pos }), el("span", { text: "UTF-8" }), el("span", { text: d.lang }),
      el("span", { text: `${d.emoji} ${d.name}` }),
    ]));

    windowsLayer.append(win);
    wireWindow(win);
    return win;
  };

  // ───────────────────────────── The coffin's bluescreen ─────────────────────────────
  const bsod = $("#bsod");
  const bsodBack = $("#bsod-back");
  const backQuips = [
    "Back to the totally real Mac",
    "Sure, it's a Mac. Go back.",
    "I saw nothing. Go back.",
  ];
  let quip = 0;
  let bsodReturnFocus = null;

  const showBluescreen = () => {
    bsodReturnFocus = document.activeElement;
    bsodBack.textContent = backQuips[quip++ % backQuips.length];
    bsod.hidden = false;
    bsodBack.focus();
  };
  const hideBluescreen = () => {
    if (bsod.hidden) return;
    bsod.hidden = true;
    bsodReturnFocus?.focus?.();
  };
  bsodBack.addEventListener("click", hideBluescreen);
  // "Press any key", as promised. Tab stays on the one button there is.
  bsod.addEventListener("keydown", (event) => {
    event.stopPropagation();
    if (event.key === "Tab") { event.preventDefault(); return; }
    if (event.key === "Enter" || event.key === " ") return; // let the button handle its own click
    event.preventDefault();
    hideBluescreen();
  });

  // ───────────────────────────── The Dock ─────────────────────────────
  const dock = $("#dock");
  const dockSepApps = $("#dock-sep-apps");

  const launch = (item) => {
    const app = item.dataset.app;
    if (app === "trash") {
      item.classList.remove("wiggle");
      void item.offsetWidth;
      item.classList.add("wiggle");
      // The coffin wiggles, then the costume slips.
      setTimeout(showBluescreen, reducedMotion ? 0 : 400);
      return;
    }
    const open = () => {
      let wins = windowsFor(app);
      if (!wins.length && app.startsWith("disguise:")) wins = [buildVSCode(disguises.get(app.slice(9)))];
      // Already on screen: nothing to do. Otherwise it takes the screen, like clicking a running app in the Dock.
      const visible = wins.find((w) => !w.hidden);
      if (visible) focusWindow(visible); else showWindow(wins[0]);
    };
    const running = item.classList.contains("running");
    if (running || reducedMotion || isPhone()) return open();
    item.classList.add("launching");
    setTimeout(() => { item.classList.remove("launching"); open(); }, 560);
  };

  const buildDockItem = (d) => {
    const item = el("button.dock-item", { type: "button", "aria-label": `${d.label} — VS Code in a ${d.emoji} costume`, dataset: { app: `disguise:${d.id}` } }, [
      el("span.icon.tile-icon", { "aria-hidden": "true", text: d.emoji, style: { "--tile": d.color } }),
      el("span.dock-label", { text: d.label }),
      el("span.dock-dot"),
    ]);
    item.addEventListener("click", () => launch(item));
    return item;
  };

  // On phones the Dock never scrolls: its icons shrink until every one of them fits the screen.
  const fitDock = () => {
    if (!isPhone()) return dock.style.removeProperty("--size");
    const items = $$(".dock-item", dock).length;
    const seps = $$(".dock-sep", dock).length;
    // Screen gutter and Dock padding, separators, 2px gaps, then 4px of padding per icon.
    const room = window.innerWidth - 12 - 14 - seps * 7 - (items + seps) * 2 - items * 4;
    dock.style.setProperty("--size", `${Math.max(24, Math.min(44, Math.floor(room / items)))}px`);
  };
  const addDisguiseToDock = (d) => { dockSepApps.before(buildDockItem(d)); fitDock(); };
  DISGUISES.forEach(addDisguiseToDock);
  window.addEventListener("resize", fitDock);
  $$(".dock-item:not([data-app^='disguise:'])").forEach((item) => item.addEventListener("click", () => launch(item)));

  // Magnification: every icon grows by how close the pointer is to its center. Hover devices only.
  const canHover = matchMedia("(hover: hover) and (pointer: fine)").matches;
  const resetMagnification = () => $$(".dock-item", dock).forEach((item) => item.style.setProperty("--mag", "1"));
  if (canHover && !reducedMotion) {
    dock.addEventListener("mousemove", (event) => {
      for (const item of $$(".dock-item", dock)) {
        const rect = item.getBoundingClientRect();
        const distance = Math.abs(event.clientX - (rect.left + rect.width / 2));
        const scale = 1 + 0.6 * Math.max(0, 1 - distance / 120);
        item.style.setProperty("--mag", scale.toFixed(3));
      }
    });
    dock.addEventListener("mouseleave", resetMagnification);
  }
  dock.addEventListener("keydown", (event) => {
    const items = $$(".dock-item", dock);
    const index = items.indexOf(document.activeElement);
    if (index < 0 || (event.key !== "ArrowRight" && event.key !== "ArrowLeft")) return;
    event.preventDefault();
    items[(index + (event.key === "ArrowRight" ? 1 : items.length - 1)) % items.length].focus();
  });

  // ───────────────────────────── Finder ─────────────────────────────
  const finderItems = $("#finder-items");
  const renderFinder = () => {
    const apps = [
      el("button.finder-item", { type: "button", dataset: { app: "code-o-ween" } }, [el("img", { src: "code-o-ween.png", alt: "", width: 56, height: 56 }), "Code-o-ween.app"]),
      ...Array.from(disguises.values(), (d) => el("button.finder-item", { type: "button", dataset: { app: `disguise:${d.id}` } }, [
        el("span.tile", { text: d.emoji, style: { "--tile": d.color }, "aria-hidden": "true" }), `VS Code - ${d.name}.app`,
      ])),
    ];
    finderItems.replaceChildren(...apps);
    apps.forEach((button) => button.addEventListener("click", () => launch(dockItemFor(button.dataset.app))));
  };
  renderFinder();

  // ───────────────────────────── Code-o-ween manager ─────────────────────────────
  // Like the real app, the window shows one thing at a time: the list of disguises, or the
  // create form after "Add More…".
  const managerList = $("#manager-list");
  const createForm = $("#create-form");
  const instanceList = $("#instance-list");
  const statusLines = [$("#list-status"), $("#status")];

  const say = (text, isError = false) => statusLines.forEach((line) => { line.textContent = text; line.classList.toggle("error", isError); });
  const showCreateForm = (show) => {
    managerList.hidden = show;
    createForm.hidden = !show;
    if (show) $("#f-name").focus();
  };

  const renderInstances = () => {
    instanceList.replaceChildren(...Array.from(disguises.values(), (d) => {
      // Each row carries its own actions, like the real list.
      const open = el("button.mac-btn.small", { type: "button", text: "Open" });
      const edit = el("button.mac-btn.small", { type: "button", text: "Edit…" });
      const remove = el("button.mac-btn.small.destructive", { type: "button", text: "🗑", "aria-label": `Remove ${d.name}`, title: `Remove ${d.name}…` });
      open.addEventListener("click", () => launch(dockItemFor(`disguise:${d.id}`)));
      edit.addEventListener("click", () => say(`Editing works in the real app. Here, ${d.name} stays as is.`));
      remove.addEventListener("click", () => say(`Removing works in the real app. Here, ${d.name} is forever.`, true));
      const row = el("li.instance-row", { dataset: { id: d.id } }, [
        el("span.tile", { text: d.emoji, style: { "--tile": d.color }, "aria-hidden": "true" }),
        el("span.instance-text", {}, [el("b", { text: d.name }), el("small", { text: `VS Code · ${presetName(d.color)}${d.isolated ? " · isolated extensions" : " · shared extensions"}` })]),
        el("span.row-actions", {}, [open, edit, remove]),
      ]);
      row.addEventListener("dblclick", (event) => { if (!event.target.closest("button")) launch(dockItemFor(`disguise:${d.id}`)); });
      return row;
    }));
  };
  renderInstances();

  $("#reload-list").addEventListener("click", () => { renderInstances(); say(`${disguises.size} disguises haunting ~/Applications/Code-o-ween/.`); });
  $("#refresh-all").addEventListener("click", () => say(`Refreshed ${disguises.size} disguises from the source app.`));
  $("#add-more").addEventListener("click", () => { showCreateForm(true); say("Ready. This is a web page; nothing touches your computer."); });
  $("#cancel-create").addEventListener("click", () => showCreateForm(false));

  // Color swatches: the real app's 15 presets as a radio group.
  const swatches = $("#swatches");
  PRESETS.forEach(([name, hex]) => {
    const input = el("input", { type: "radio", name: "color", value: hex, "aria-label": name });
    if (name === "orange") input.checked = true;
    swatches.append(el("label.swatch", { title: name }, [input, el("i", { style: { "--c": hex } })]));
  });
  const chosenColor = () => ($("input[name=color]:checked", swatches) || {}).value || "#BF4F00";
  const chooseColor = (hex) => { const input = $(`input[name=color][value="${hex}"]`, swatches); if (input) input.checked = true; };

  // The emoji picker: a grid of suggestions, a field for any other one. One emoji at a time:
  // whatever is typed replaces the current one, so inserting into a filled field picks rather than appends.
  const EMOJI = ["🎃", "👻", "🧛", "🧙", "🕷️", "💀", "🦇", "🧟", "🕸️", "🔮", "🧪", "🐈‍⬛", "🍬", "🌙", "⚡️", "🔥", "🚀", "🛠️", "🧩", "🐙", "🦄", "🐸", "🌵", "🍕"];
  const emojiField = $("#f-emoji");
  const emojiGrid = $("#emoji-grid");
  const lastGrapheme = (text) => {
    if (!text) return "";
    if (typeof Intl !== "undefined" && Intl.Segmenter) {
      const parts = Array.from(new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text), (p) => p.segment);
      return parts[parts.length - 1] || "";
    }
    return Array.from(text).pop() || "";
  };
  const markEmoji = () => $$(".emoji-btn", emojiGrid).forEach((button) => button.setAttribute("aria-checked", String(button.dataset.emoji === emojiField.value)));
  const setEmoji = (value) => { emojiField.value = lastGrapheme(value.trim()); markEmoji(); };
  EMOJI.forEach((item) => {
    const button = el("button.emoji-btn", { type: "button", text: item, role: "radio", "aria-label": item, dataset: { emoji: item } });
    button.addEventListener("click", () => setEmoji(item));
    emojiGrid.append(button);
  });
  emojiField.addEventListener("input", () => setEmoji(emojiField.value));
  $("#f-more-emoji").addEventListener("click", () => { emojiField.focus(); say("The real app opens the emoji palette (⌃⌘Space). Here, type one in."); });
  markEmoji();

  const costume = $("#f-costume");
  costume.addEventListener("change", () => {
    const option = costume.selectedOptions[0];
    if (!option.dataset.emoji) return; // Custom: keep what is there
    setEmoji(option.dataset.emoji);
    chooseColor(option.dataset.color);
  });

  const iconPicker = $("#f-icon");
  const emojiRow = $("#emoji-row");
  iconPicker.addEventListener("change", () => {
    emojiRow.hidden = iconPicker.value !== "Emoji";
    if (iconPicker.value === "Image") say("The real app lets you pick an image file. This mock has none.");
  });

  const appPicker = $("#f-app");
  const createButton = $("#create");
  const tintRow = $("#f-tint").closest(".row");
  const folderRow = $("#f-folder").closest(".row");
  const extRow = $("#f-ext").closest(".row");
  appPicker.addEventListener("change", () => {
    const app = appPicker.value;
    const other = app === "Other app…";
    createButton.textContent = `Disguise ${other ? "app" : app === "Visual Studio Code" ? "VS Code" : app}`;
    tintRow.hidden = folderRow.hidden = extRow.hidden = other;
    if (other) say("The real app lets you pick any editor. This mock only knows VS Code.");
  });
  $("#f-choose").addEventListener("click", () => { $("#f-folder").value = "~/code/side-project-c"; say("Chose a folder. Empty, like every side project C."); });

  createForm.addEventListener("submit", (event) => {
    event.preventDefault();
    const name = $("#f-name").value.trim();
    const emoji = emojiField.value.trim() || "🎃";
    const color = chosenColor();
    if (!name) return say("Give it a name first. Even ghosts have names.", true);
    if (name.startsWith("-")) return say("Names cannot start with “-”. The command line would take it personally.", true);
    if (appPicker.value !== "Visual Studio Code") return say(`Only the VS Code recipe is verified. ${appPicker.value} stays in the real app's warning list.`, true);
    const id = slugify(name);
    if (disguises.has(id)) return say(`There is already a disguise called "${disguises.get(id).name}". Names are unique across apps.`, true);
    const folder = $("#f-folder").value.trim() || `~/code/${id}`;
    const d = {
      id, name, label: name, emoji, color, folder, repo: folder.split("/").pop() || id, branch: "main", lang: "Plain Text", pos: "Ln 1, Col 1",
      file: "README.md", isolated: $("#f-ext").checked,
      tree: [["file active", "README.md", 0, "M↓"], ["file", ".gitignore", 0, "◦"]],
      tabs: ["README.md"],
      code: [
        [["c", `# ${name}`]], [],
        [["", `A new disguise. Fresh costume, empty folder, infinite potential.`]], [],
        [["c", `<!-- created with: code-o-ween create "${name}" --emoji ${emoji} --color ${presetName(color)} --folder ${folder} -->`]],
      ],
      terminal: [
        [["prompt", "$ "], ["", `code-o-ween create "${name}" --emoji ${emoji} --color ${presetName(color)} --folder ${folder}${$("#f-ext").checked ? " --extensions isolated" : ""}`]],
        [["dim", `Created ~/Applications/Code-o-ween/VS Code - ${name}.app`]],
      ],
    };
    disguises.set(id, d);
    addDisguiseToDock(d);
    renderInstances();
    renderFinder();
    $("#f-name").value = "";
    $("#f-folder").value = "";
    // Back to the list, which now has the new disguise.
    showCreateForm(false);
    say(`"${name}" has risen. It is in the Dock now.`);
    const item = dockItemFor(`disguise:${id}`);
    if (!reducedMotion) { item.classList.add("launching"); setTimeout(() => item.classList.remove("launching"), 1100); }
  });

  // ───────────────────────────── The browser's one toy ─────────────────────────────
  const answers = [
    "No.",
    "Still no.",
    "Have you tried Profiles? They're built in. No ghosts.",
    "Ask again after Halloween.",
    "It's a re-signed copy of VS Code. Sit with that for a moment.",
    "Nine hundred megabytes. Per costume.",
    "Current reading: 51% trick, 49% treat. Margin of error: all of it.",
    "…fine. But read the README first, and only the VS Code one is verified.",
    "Afraid? You can do it by hand. Scroll down: six steps, no script.",
    "You scrolled this far. The answer is still no, but with affection.",
  ];
  let step = 0;
  const verdict = $("#verdict");
  $("#ask").addEventListener("click", () => { verdict.textContent = answers[step % answers.length]; step += 1; });
  $$("[data-open]").forEach((button) => button.addEventListener("click", () => launch(dockItemFor(button.dataset.open))));

  // ───────────────────────────── Odds and ends ─────────────────────────────
  $$(".window", windowsLayer).forEach(wireWindow);
  $("#sticky-close").addEventListener("click", () => $("#sticky").remove());

  const clock = $("#clock");
  const tick = () => {
    const now = new Date();
    const date = now.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
    const time = now.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    clock.textContent = `${date}  ${time}`;
    clock.dateTime = now.toISOString();
  };
  tick();
  setInterval(tick, 15000);

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      const top = $(".window.focused");
      if (top && !top.querySelector(":focus")) closeWindow(top);
    }
  });

  // Lights on: the browser shows the page, like a Mac that logged in with Safari still open.
  const browser = $(".window.browser");
  browser.dataset.width = "880";
  browser.dataset.height = "640";
  $(".window.manager").dataset.width = "600";
  $(".window.manager").dataset.height = "660";
  $(".window.finder").dataset.width = "680";
  $(".window.finder").dataset.height = "420";
  // The markup ships the browser open so the page reads without script; hide it to open it properly.
  browser.hidden = true;
  showWindow(browser);

  // The download button links to a fixed release in the markup, which keeps working without
  // script or network. When GitHub answers, it is pointed at the newest release's disk image.
  // The repository is read from that link, so the page carries its address in one place.
  const download = $("#download");
  const downloadMeta = $("#download-meta");
  if (download && "fetch" in window) {
    const [owner, repo] = new URL(download.href).pathname.split("/").slice(1, 3);
    fetch(`https://api.github.com/repos/${owner}/${repo}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } })
      .then((response) => (response.ok ? response.json() : Promise.reject(new Error(response.statusText))))
      .then((release) => {
        const asset = (release.assets || []).find((item) => item.name.endsWith(".dmg"));
        if (!asset) return;
        download.href = asset.browser_download_url;
        if (downloadMeta) downloadMeta.textContent = `${release.tag_name} · ${(asset.size / 1048576).toFixed(1)} MB`;
      })
      .catch(() => {});
  }
})();
