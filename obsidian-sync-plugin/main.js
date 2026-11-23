var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// main.ts
var main_exports = {};
__export(main_exports, {
  default: () => KOReaderSyncPlugin
});
module.exports = __toCommonJS(main_exports);
var import_obsidian = require("obsidian");
var http = __toESM(require("http"));
var crypto = __toESM(require("crypto"));
var os = __toESM(require("os"));
var DEFAULT_SETTINGS = {
  serverEnabled: false,
  port: 7777,
  username: "koreader",
  password: "koreader",
  annotationsFolder: "KOReader"
};
var KOReaderSyncPlugin = class extends import_obsidian.Plugin {
  constructor() {
    super(...arguments);
    this.server = null;
    // In-memory progress store keyed by document hash
    this.progressStore = /* @__PURE__ */ new Map();
    // Map document_hash → file path so we can update progress in existing notes
    this.hashToPath = /* @__PURE__ */ new Map();
  }
  async onload() {
    await this.loadSettings();
    this.addSettingTab(new KOReaderSyncSettingTab(this.app, this));
    this.addRibbonIcon("book-open", "KOReader Sync", () => {
      var _a;
      if ((_a = this.server) == null ? void 0 : _a.listening) {
        new import_obsidian.Notice(
          `KOReader Sync running on port ${this.settings.port}
Connect KOReader to: http://${getLocalIP()}:${this.settings.port}`
        );
      } else {
        new import_obsidian.Notice("KOReader Sync server is stopped. Enable it in settings.");
      }
    });
    this.addCommand({
      id: "koreader-sync-toggle",
      name: "Toggle sync server",
      callback: async () => {
        var _a;
        if ((_a = this.server) == null ? void 0 : _a.listening) {
          this.stopServer();
        } else {
          await this.startServer();
        }
      }
    });
    if (this.settings.serverEnabled) {
      this.app.workspace.onLayoutReady(() => this.startServer());
    }
  }
  onunload() {
    this.stopServer();
  }
  // -------------------------------------------------------------------------
  // Server lifecycle
  // -------------------------------------------------------------------------
  async startServer() {
    if (!import_obsidian.Platform.isDesktop) {
      new import_obsidian.Notice("KOReader Sync requires the desktop app.");
      return;
    }
    if (this.server) {
      this.stopServer();
    }
    this.server = http.createServer((req, res) => {
      this.handleRequest(req, res).catch((err) => {
        console.error("[KOReader Sync] unhandled error:", err);
        if (!res.headersSent) {
          res.writeHead(500);
          res.end(JSON.stringify({ error: "Internal server error" }));
        }
      });
    });
    this.server.on("error", (err) => {
      if (err.code === "EADDRINUSE") {
        new import_obsidian.Notice(
          `KOReader Sync: port ${this.settings.port} is already in use.`
        );
      } else {
        new import_obsidian.Notice(`KOReader Sync server error: ${err.message}`);
      }
    });
    await new Promise((resolve) => {
      this.server.listen(this.settings.port, "0.0.0.0", () => {
        new import_obsidian.Notice(
          `KOReader Sync started on port ${this.settings.port}
Server address: http://${getLocalIP()}:${this.settings.port}`
        );
        resolve();
      });
    });
  }
  stopServer() {
    if (this.server) {
      this.server.close();
      this.server = null;
      new import_obsidian.Notice("KOReader Sync server stopped.");
    }
  }
  // -------------------------------------------------------------------------
  // Request routing
  // -------------------------------------------------------------------------
  async handleRequest(req, res) {
    var _a;
    const pathname = ((_a = req.url) != null ? _a : "/").split("?")[0];
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader(
      "Access-Control-Allow-Methods",
      "GET, POST, PUT, DELETE, OPTIONS"
    );
    res.setHeader(
      "Access-Control-Allow-Headers",
      "Content-Type, x-auth-user, x-auth-key"
    );
    res.setHeader("Content-Type", "application/json");
    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }
    if (pathname === "/users/create" && req.method === "POST") {
      return this.routeCreateUser(req, res);
    }
    if (pathname === "/users/auth" && req.method === "GET") {
      return this.routeAuth(req, res);
    }
    if (pathname === "/syncs/progress" && req.method === "PUT") {
      return this.routeUpdateProgress(req, res);
    }
    if (pathname.startsWith("/syncs/progress/") && req.method === "GET") {
      const docHash = decodeURIComponent(
        pathname.slice("/syncs/progress/".length)
      );
      return this.routeGetProgress(req, res, docHash);
    }
    if (pathname === "/api/annotations" && req.method === "POST") {
      return this.routeAnnotations(req, res);
    }
    res.writeHead(404);
    res.end(JSON.stringify({ error: "Not found" }));
  }
  // -------------------------------------------------------------------------
  // Auth helpers
  // -------------------------------------------------------------------------
  isAuthenticated(req) {
    const user = req.headers["x-auth-user"];
    const key = req.headers["x-auth-key"];
    if (!user || !key)
      return false;
    const expectedKey = crypto.createHash("md5").update(this.settings.password).digest("hex");
    return user === this.settings.username && key.toLowerCase() === expectedKey.toLowerCase();
  }
  readBody(req) {
    return new Promise((resolve, reject) => {
      let raw = "";
      req.on("data", (chunk) => raw += chunk.toString());
      req.on("end", () => {
        try {
          resolve(raw ? JSON.parse(raw) : {});
        } catch (e) {
          resolve({});
        }
      });
      req.on("error", reject);
    });
  }
  // -------------------------------------------------------------------------
  // Route handlers
  // -------------------------------------------------------------------------
  async routeCreateUser(req, res) {
    const body = await this.readBody(req);
    if (!body.username || !body.password) {
      res.writeHead(400);
      res.end(JSON.stringify({ error: "username and password required" }));
      return;
    }
    res.writeHead(200);
    res.end(JSON.stringify({ authorized: "OK" }));
  }
  async routeAuth(req, res) {
    if (this.isAuthenticated(req)) {
      res.writeHead(200);
      res.end(JSON.stringify({ authorized: "OK" }));
    } else {
      res.writeHead(401);
      res.end(JSON.stringify({ error: "Unauthorized" }));
    }
  }
  async routeUpdateProgress(req, res) {
    var _a, _b;
    if (!this.isAuthenticated(req)) {
      res.writeHead(401);
      res.end(JSON.stringify({ error: "Unauthorized" }));
      return;
    }
    const body = await this.readBody(req);
    const document2 = body.document;
    if (!document2) {
      res.writeHead(400);
      res.end(JSON.stringify({ error: "document field required" }));
      return;
    }
    const record = {
      document: document2,
      progress: (_a = body.progress) != null ? _a : "",
      percentage: (_b = body.percentage) != null ? _b : 0,
      device: body.device,
      device_id: body.device_id,
      timestamp: Math.floor(Date.now() / 1e3)
    };
    this.progressStore.set(document2, record);
    const existingPath = this.hashToPath.get(document2);
    if (existingPath) {
      await this.patchProgressInNote(existingPath, record);
    }
    res.writeHead(200);
    res.end(JSON.stringify({ document: document2, timestamp: record.timestamp }));
  }
  async routeGetProgress(req, res, docHash) {
    if (!this.isAuthenticated(req)) {
      res.writeHead(401);
      res.end(JSON.stringify({ error: "Unauthorized" }));
      return;
    }
    const record = this.progressStore.get(docHash);
    if (record) {
      res.writeHead(200);
      res.end(JSON.stringify(record));
    } else {
      res.writeHead(404);
      res.end(JSON.stringify({ error: "No progress found" }));
    }
  }
  async routeAnnotations(req, res) {
    var _a, _b;
    if (!this.isAuthenticated(req)) {
      res.writeHead(401);
      res.end(JSON.stringify({ error: "Unauthorized" }));
      return;
    }
    const body = await this.readBody(req);
    if (!body.title) {
      res.writeHead(400);
      res.end(JSON.stringify({ error: "title field required" }));
      return;
    }
    try {
      const filePath = await this.upsertBookNote(body);
      if (body.document_hash && filePath) {
        this.hashToPath.set(body.document_hash, filePath);
      }
      res.writeHead(200);
      res.end(
        JSON.stringify({
          status: "ok",
          annotations: (_b = (_a = body.annotations) == null ? void 0 : _a.length) != null ? _b : 0,
          file: filePath
        })
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      res.writeHead(500);
      res.end(JSON.stringify({ error: msg }));
    }
  }
  // -------------------------------------------------------------------------
  // Vault helpers
  // -------------------------------------------------------------------------
  async ensureFolder(folderPath) {
    const normalized = (0, import_obsidian.normalizePath)(folderPath);
    if (!this.app.vault.getAbstractFileByPath(normalized)) {
      await this.app.vault.createFolder(normalized);
    }
  }
  sanitize(name) {
    return name
      .replace(/\r?\n/g, " & ")          // KOReader joins multiple authors with \n → "Author A & Author B"
      .replace(/[\\/:*?"<>|#^[\]]/g, "-") // strip characters illegal in filenames
      .replace(/\s+/g, " ")              // collapse any leftover double spaces
      .trim();
  }
  /** Create or fully overwrite the book's Markdown note. Returns the file path. */
  async upsertBookNote(book) {
    var _a, _b;
    await this.ensureFolder(this.settings.annotationsFolder);
    const filename = (book.author
      ? this.sanitize(book.title) + " - " + this.sanitize(book.author)
      : this.sanitize(book.title)) + ".md";
    const filePath = (0, import_obsidian.normalizePath)(
      `${this.settings.annotationsFolder}/${filename}`
    );
    const content = this.renderBookNote(book);
    const existing = this.app.vault.getAbstractFileByPath(filePath);
    if (existing instanceof import_obsidian.TFile) {
      await this.app.vault.modify(existing, content);
    } else {
      await this.app.vault.create(filePath, content);
    }
    new import_obsidian.Notice(
      `KOReader: synced "${book.title}" \u2014 ${(_b = (_a = book.annotations) == null ? void 0 : _a.length) != null ? _b : 0} annotations`
    );
    return filePath;
  }
  /** Patch only the reading-progress section inside an existing note. */
  async patchProgressInNote(filePath, rec) {
    const file = this.app.vault.getAbstractFileByPath(filePath);
    if (!(file instanceof import_obsidian.TFile))
      return;
    const content = await this.app.vault.read(file);
    const percent = Math.round(rec.percentage * 100);
    const date = new Date(rec.timestamp * 1e3).toISOString().slice(0, 10);
    const updated = content.replace(/^reading_progress:.*$/m, `reading_progress: ${percent}%`).replace(/^last_sync:.*$/m, `last_sync: ${date}`).replace(
      /^(- \*\*Progress:\*\* ).*$/m,
      `$1${percent}%`
    ).replace(
      /^(- \*\*Position:\*\* ).*$/m,
      `$1${rec.progress}`
    );
    if (updated !== content) {
      await this.app.vault.modify(file, updated);
    }
  }
  // -------------------------------------------------------------------------
  // Markdown renderer
  // -------------------------------------------------------------------------
  renderBookNote(book) {
    var _a;
    const today = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
    const percent = book.percentage !== void 0 ? `${Math.round(book.percentage * 100)}%` : "unknown";
    const lines = [];
    lines.push("---");
    lines.push(`title: "${esc(book.title)}"`);
    if (book.author) {
      // KOReader separates co-authors with \n. Render as a YAML list so
      // Obsidian treats the property as "List" type (one author per line).
      const authors = book.author.split("\n").map((a) => a.trim()).filter(Boolean);
      if (authors.length === 1) {
        lines.push(`author: "${esc(authors[0])}"`);
      } else {
        lines.push("author:");
        for (const a of authors) lines.push(`  - "${esc(a)}"`);
      }
    }
    if (book.series)
      lines.push(`series: "${esc(book.series)}"`);
    if (book.language)
      lines.push(`language: "${esc(book.language)}"`);
    if (book.document_hash)
      lines.push(`document_hash: "${book.document_hash}"`);
    lines.push(`reading_progress: ${percent}`);
    lines.push(`last_sync: ${today}`);
    lines.push("tags:");
    lines.push("  - koreader");
    lines.push("  - book-notes");
    lines.push("---");
    lines.push("");
    lines.push(`# ${book.title}`);
    lines.push("");
    if (book.author || book.series) {
      if (book.author) {
        const authorsDisplay = book.author.split("\n").map((a) => a.trim()).filter(Boolean).join(" & ");
        lines.push(`**Author:** ${authorsDisplay}  `);
      }
      if (book.series)
        lines.push(`**Series:** ${book.series}  `);
      lines.push("");
    }
    lines.push("## Reading Progress");
    lines.push("");
    lines.push(`- **Progress:** ${percent}`);
    if (book.progress)
      lines.push(`- **Position:** ${book.progress}`);
    if (book.last_device)
      lines.push(`- **Device:** ${book.last_device}`);
    lines.push(`- **Last synced:** ${today}`);
    lines.push("");
    lines.push("## Highlights & Annotations");
    lines.push("");
    const annotations = (_a = book.annotations) != null ? _a : [];
    if (annotations.length === 0) {
      lines.push("*No annotations synced yet.*");
      lines.push("");
    } else {
      let currentChapter = "";
      for (const ann of annotations) {
        if (ann.chapter && ann.chapter !== currentChapter) {
          currentChapter = ann.chapter;
          lines.push(`### ${currentChapter}`);
          lines.push("");
        }
        if (ann.highlighted_text) {
          const quote = ann.highlighted_text.split("\n").map((l) => `> ${l}`).join("\n");
          lines.push(quote);
          lines.push("");
        }
        if (ann.note) {
          lines.push(`**Note:** ${ann.note}`);
          lines.push("");
        }
        const meta = [];
        if (ann.page)
          meta.push(`Page ${ann.page}`);
        if (ann.datetime)
          meta.push(ann.datetime);
        if (meta.length) {
          lines.push(`*${meta.join(" \xB7 ")}*`);
          lines.push("");
        }
        lines.push("---");
        lines.push("");
      }
    }
    lines.push(`*Synced via KOReader Sync on ${today}*`);
    return lines.join("\n");
  }
  // -------------------------------------------------------------------------
  // Settings persistence
  // -------------------------------------------------------------------------
  async loadSettings() {
    this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
  }
  async saveSettings() {
    await this.saveData(this.settings);
  }
};
var KOReaderSyncSettingTab = class extends import_obsidian.PluginSettingTab {
  constructor(app, plugin) {
    super(app, plugin);
    this.plugin = plugin;
  }
  display() {
    var _a;
    const { containerEl } = this;
    containerEl.empty();
    containerEl.createEl("h2", { text: "KOReader Sync" });
    new import_obsidian.Setting(containerEl).setName("Enable sync server").setDesc("Start the KOSync-compatible HTTP server inside Obsidian.").addToggle(
      (toggle) => toggle.setValue(this.plugin.settings.serverEnabled).onChange(async (value) => {
        this.plugin.settings.serverEnabled = value;
        await this.plugin.saveSettings();
        if (value) {
          await this.plugin.startServer();
        } else {
          this.plugin.stopServer();
        }
        this.display();
      })
    );
    const statusDiv = containerEl.createDiv({
      cls: "koreader-sync-status"
    });
    if ((_a = this.plugin.server) == null ? void 0 : _a.listening) {
      const ip = getLocalIP();
      statusDiv.createEl("p", {
        text: `\u2705 Server running \u2014 point KOReader to: http://${ip}:${this.plugin.settings.port}`
      });
    } else {
      statusDiv.createEl("p", { text: "\u26D4 Server stopped." });
    }
    containerEl.createEl("h3", { text: "Connection" });
    new import_obsidian.Setting(containerEl).setName("Port").setDesc("Default: 7777. Restart the server after changing.").addText(
      (text) => text.setPlaceholder("7777").setValue(String(this.plugin.settings.port)).onChange(async (value) => {
        const port = parseInt(value, 10);
        if (port > 0 && port < 65536) {
          this.plugin.settings.port = port;
          await this.plugin.saveSettings();
        }
      })
    );
    new import_obsidian.Setting(containerEl).setName("Username").setDesc("Must match the username configured in KOReader.").addText(
      (text) => text.setValue(this.plugin.settings.username).onChange(async (value) => {
        this.plugin.settings.username = value;
        await this.plugin.saveSettings();
      })
    );
    new import_obsidian.Setting(containerEl).setName("Password").setDesc("Must match the password configured in KOReader.").addText((text) => {
      text.inputEl.type = "password";
      text.setValue(this.plugin.settings.password).onChange(async (value) => {
        this.plugin.settings.password = value;
        await this.plugin.saveSettings();
      });
      return text;
    });
    containerEl.createEl("h3", { text: "Vault" });
    new import_obsidian.Setting(containerEl).setName("Annotations folder").setDesc(
      "Vault folder where book Markdown files are stored. Will be created if it doesn't exist."
    ).addText((text) => {
      var _a2;
      const datalist = document.createElement("datalist");
      datalist.id = "koreader-folder-list";
      this.app.vault.getAllFolders().forEach((f) => {
        const opt = document.createElement("option");
        opt.value = f.path;
        datalist.appendChild(opt);
      });
      text.inputEl.setAttribute("list", "koreader-folder-list");
      (_a2 = text.inputEl.parentElement) == null ? void 0 : _a2.appendChild(datalist);
      text.setPlaceholder("KOReader").setValue(this.plugin.settings.annotationsFolder).onChange(async (value) => {
        this.plugin.settings.annotationsFolder = value.trim();
        await this.plugin.saveSettings();
      });
      return text;
    });
    containerEl.createEl("h3", { text: "API Endpoints" });
    containerEl.createEl("p", {
      text: "KOReader's built-in KOSync plugin uses the standard endpoints. The /api/annotations endpoint is called by the companion KOReader plugin."
    });
    const endpointList = containerEl.createEl("ul");
    const endpoints = [
      "POST /users/create \u2014 register (accept any credentials)",
      "GET  /users/auth   \u2014 authenticate",
      "PUT  /syncs/progress \u2014 update reading position",
      "GET  /syncs/progress/:hash \u2014 get reading position",
      "POST /api/annotations \u2014 sync full book with highlights (companion plugin)"
    ];
    endpoints.forEach((e) => endpointList.createEl("li", { text: e }));
    containerEl.createEl("h3", { text: "Support" });
    new import_obsidian.Setting(containerEl).setName("Report a problem or ask a question").setDesc(
      "Opens the support form in your browser. It files an issue on GitHub for you; no GitHub account needed, and your e-mail address is not published."
    ).addButton(
      (button) => button.setButtonText("Open support form").onClick(() => {
        const params = new URLSearchParams({
          app: "koreader-obsidian-sync",
          version: this.plugin.manifest.version,
          os: `Obsidian ${import_obsidian.apiVersion || ""} on ${process.platform}`.trim()
        });
        window.open(`https://support.justinmeijer.nl/?${params.toString()}`);
      })
    );
  }
};
function getLocalIP() {
  var _a;
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const alias of (_a = ifaces[name]) != null ? _a : []) {
      if (alias.family === "IPv4" && !alias.internal) {
        return alias.address;
      }
    }
  }
  return "127.0.0.1";
}
function esc(s) {
  return s.replace(/"/g, '\\"');
}
