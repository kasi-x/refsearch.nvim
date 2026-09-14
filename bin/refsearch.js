#!/usr/bin/env node
/**
 * jk-search: ジャパンナレッジLib 検索スクリプト (Puppeteer)。
 *
 * 専用プロファイルの Chrome (常駐) で検索を実行し、結果を JSON で stdout に
 * 出力する。メインブラウザには一切触れない。
 *
 * フロー:
 *   1. 専用プロファイルの Chrome に接続 (なければ起動)
 *   2. リダイレクタ経由で検索ページ (基本検索) を開く (OpenAthens セッション確立)
 *   3. 未ログインならログインが必要 (auth) を返す
 *   4. 検索フォーム (#sword) に検索語を入力して送信
 *   5. 結果リンクを収集して JSON で出力
 *
 * 使い方:
 *   node jk-search.js <検索語>
 *
 * 出力 (JSON):
 *   {
 *     "status": "ok" | "auth" | "full" | "error",
 *     "query": "実験",
 *     "total": 706,
 *     "exact": [ { "title", "dict", "snippet", "url" } ],
 *     "results": [ ... ]
 *   }
 *
 * 環境変数:
 *   JK_CHROME           Chrome 実行ファイル (既定: /usr/bin/google-chrome)
 *   JK_PROFILE          専用プロファイル (既定: ~/.local/share/jk-search/profile)
 *   JK_PORT             CDP デバッグポート (既定: 9222)
 *   JK_REDIRECTOR       OpenAthens リダイレクタ URL (必須)。
 *                       所属機関のものを指定する。
 *                       例: https://go.openathens.net/redirector/<your-domain>
 *   JK_PROXY            OpenAthens proxy のベース URL (必須)。
 *                       例: https://<resource>.proxy.openathens.net
 */

const puppeteer = require("puppeteer-core");
const { spawn } = require("child_process");
const path = require("path");
const os = require("os");
const http = require("http");

const CHROME = process.env.JK_CHROME || "/usr/bin/google-chrome";
const PROFILE =
  process.env.JK_PROFILE || path.join(os.homedir(), ".local/share/jk-search/profile");
const PORT = Number(process.env.JK_PORT || 9222);
// 所属機関固有の設定は既定値を持たない。環境変数 (または Neovim 側の
// setup({ redirector = ..., proxy = ... })) で必ず指定する。
const REDIRECTOR = process.env.JK_REDIRECTOR || "";
const PROXY = process.env.JK_PROXY || "";
// JK_HEADLESS=1 でヘッドレス Chrome を起動する (可視ウィンドウが出ない)。
// ログインが必要な場合は可視で起動して手動ログインする。
const HEADLESS = process.env.JK_HEADLESS === "1";

const UA =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36";

const CDP = `http://127.0.0.1:${PORT}`;

// ---------------------------------------------------------------------------
// 小さなヘルパー
// ---------------------------------------------------------------------------

function result(status, extra = {}) {
  return JSON.stringify({ status, ...extra });
}

// リダイレクタ経由の URL に変換する。
function redirectorUrl(target) {
  return `${REDIRECTOR}?url=${encodeURIComponent(target)}`;
}

// 検索ページ (基本検索) への入り口。必ずリダイレクタ経由で入る。
// OpenAthens はリダイレクタ経由でセッションを (再) 確立するため、
// proxy URL (SEARCH_PAGE_URL) を直接開くと 403 になり「ログイン必要」と
// 誤判定される (セッションが切れている時に発生)。
function searchEntryUrl() {
  return redirectorUrl("https://japanknowledge.com/lib/search/basic/");
}

// 検索ページ (直接開く)。cookie が有効ならログイン済みで表示される。
const SEARCH_PAGE_URL = `${PROXY}/lib/search/basic/`;

// 検索・初期化に必要な機関固有設定 (JK_REDIRECTOR / JK_PROXY) を確認する。
// 未設定ならエラー JSON を出力して終了する (--fetch / --open-tabs は対象外)。
function requireInstitutionConfig() {
  if (REDIRECTOR !== "" && PROXY !== "") {
    return;
  }
  console.log(
    result("error", {
      message:
        "JK_REDIRECTOR / JK_PROXY が未設定です。所属機関の OpenAthens " +
        "リダイレクタ URL と proxy のベース URL を設定してください",
    })
  );
  process.exit(1);
}

// 指定 URL が「検索結果ページ」かどうか。
function isSearchPage(url) {
  return url.includes("/lib/search/basic");
}

// 指定 URL が「ログインが絡むページ」かどうか。
function isLoginUrl(url) {
  return (
    url.includes("login.openathens.net") ||
    url.includes("/auth/login/error") ||
    url.includes("shib.sys.thers.ac.jp")
  );
}

// ---------------------------------------------------------------------------
// Chrome の接続 / 起動
// ---------------------------------------------------------------------------

// 指定ポートの CDP に接続できるか確認する。
async function tryConnect() {
  try {
    // Chrome 起動中の接続は応答しないことがあるため、fetch にタイムアウトを付ける
    const res = await fetch(`${CDP}/json/version`, {
      signal: AbortSignal.timeout(2000),
    });
    if (!res.ok) {
      return null;
    }
    return await puppeteer.connect({
      browserURL: CDP,
      defaultViewport: null,
    });
  } catch (e) {
    return null;
  }
}

// 専用プロファイルの Chrome を起動する。
function spawnChrome() {
  const args = [
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--disable-blink-features=AutomationControlled",
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${PROFILE}`,
    "--no-first-run",
    "--no-default-browser-check",
  ];
  if (HEADLESS) {
    args.push("--headless=new");
  }
  args.push("about:blank");
  return spawn(CHROME, args, { stdio: "ignore", detached: true });
}

// 既に起動済みなら接続し、無ければ起動して接続する。
// 戻り値: { browser, chrome, existing }
async function connectOrLaunch() {
  // 1. 起動済みか確認
  const existing = await tryConnect();
  if (existing) {
    return { browser: existing, chrome: null, existing: true };
  }

  // 2. 新規起動
  const chrome = spawnChrome();

  // 起動完了まで最大 30 秒待つ
  let browser = null;
  for (let i = 0; i < 60; i++) {
    browser = await tryConnect();
    if (browser) {
      break;
    }
    await new Promise((r) => setTimeout(r, 500));
  }

  if (!browser) {
    chrome.kill();
    throw new Error("failed to connect to Chrome CDP");
  }

  return { browser, chrome, existing: false };
}

// Puppeteer 検出回避などを新しいページに適用する。
async function preparePage(page) {
  await page.setUserAgent(UA);
  await page.evaluateOnNewDocument(() => {
    Object.defineProperty(navigator, "webdriver", { get: () => undefined });
    delete navigator.__proto__.webdriver;
    Object.defineProperty(navigator, "plugins", {
      get: () => [1, 2, 3, 4, 5],
    });
    window.chrome = window.chrome || { runtime: {} };
    Object.defineProperty(navigator, "languages", {
      get: () => ["ja-JP", "ja", "en"],
    });
  });
}

// ---------------------------------------------------------------------------
// 後始末
// ---------------------------------------------------------------------------

// 既存の常駐 Chrome なら接続だけ切り (Chrome は残す)、
// 新規起動した Chrome なら終了する。
async function cleanup(browser, chrome, existing) {
  if (!browser) {
    return;
  }
  if (existing) {
    await browser.disconnect().catch(() => {});
  } else {
    await browser.close().catch(() => {});
    chrome.kill();
  }
}

// ---------------------------------------------------------------------------
// 各ステップ
// ---------------------------------------------------------------------------

// 検索ページへ直接遷移する。
// cookie が有効な間は、リダイレクタを経由せず直接開ける (ログイン済み)。
// 未ログインならログイン画面へリダイレクトされる。
async function gotoEntry(page) {
  try {
    await page.goto(searchEntryUrl(), {
      waitUntil: "domcontentloaded",
      timeout: 45000,
    }).catch(() => {});
    // リダイレクタ -> OpenAthens SAML (セッション再確立) -> (検索 or ログイン) の
    // チェーンは数秒かかる。ログイン URL はセッション再確立でも一時的に現れる
    // ため、検索フォーム (#sword) の出現を最大15秒待ってから確定する
    // (Promise.race で必ず終了する。出なければ後段で auth 判定する)。
    await Promise.race([
      page.waitForSelector("#sword", { timeout: 15000 }).catch(() => null),
      new Promise((r) => setTimeout(r, 15000)),
    ]);
    await new Promise((r) => setTimeout(r, 500));
    return { ok: true, url: page.url() };
  } catch (e) {
    return { ok: false, error: e, url: page.url() };
  }
}

// ページの状態を判定する。
//   - "auth":   ログインが必要 (ログイン画面・認証エラー)
//   - "full":   同時接続数オーバー
//   - "ready":  ログイン済みで利用可能
async function judgePageState(page) {
  const url = page.url();
  // リダイレクトチェーンがまだ進行中だと evaluate が
  // "Execution context was destroyed" で失敗するため、読めるまでリトライする。
  let title = "";
  let bodyText = "";
  for (let i = 0; i < 10; i++) {
    try {
      title = await page.title();
      bodyText = await page.evaluate(
        () => (document.body ? document.body.innerText : "")
      );
      break;
    } catch (e) {
      await new Promise((r) => setTimeout(r, 500));
    }
  }

  // ログイン/認証エラー系を先に判定する。認証エラーページの本文にも
  // 「アクセス」が含まれるため、同時接続オーバー (full) 判定より先に行う。
  if (
    isLoginUrl(url) ||
    title.includes("認証エラー") ||
    title.includes("Forbidden") ||
    bodyText.includes("403")
  ) {
    return "auth";
  }
  if (bodyText.includes("アクセス") || bodyText.includes("超過")) {
    return "full";
  }
  return "ready";
}

// ログインが必要な状態かを確認する。
// 直接検索ページを開いてログイン画面に飛ばされたら、リダイレクタ経由で
// ログインし直す。cookie が有効ならそのまま検索できる。
async function ensureLoggedIn(page) {
  // ログイン済み (検索フォームがある) なら何もしない
  const hasSword = await page.$("#sword").catch(() => null);
  if (hasSword) {
    return { loggedIn: true, clicked: false };
  }

  // ログイン画面 (OpenAthens) に飛ばされた場合、リダイレクタ経由で検索ページに
  // 再入場してセッションを (再) 確立する。
  const url = page.url();
  if (isLoginUrl(url) || url.includes("login")) {
    try {
      await page.goto(searchEntryUrl(), {
        waitUntil: "domcontentloaded",
        timeout: 45000,
      });
      await new Promise((r) => setTimeout(r, 3000));
    } catch (e) {
      // 遷移失敗は無視 (次の判定で確認)
    }
  }

  // 検索フォーム (#sword) が表示されればログイン済み。
  // 表示されなければ手動ログインが必要 (auth を返す)。
  const swordNow = await page.$("#sword").catch(() => null);
  if (swordNow) {
    return { loggedIn: true, clicked: false };
  }
  return { loggedIn: false, clicked: false, needsLogin: true };
}

// 現在のページが検索ページでなければ、検索ページ (基本検索) へ移動する。
// ログイン直後はトップページにいる場合があるので、ヘッダの「基本検索」
// リンクをクリックする。
async function goToSearchPage(page) {
  // 既に検索ページなら何もしない
  if (page.url().includes("/lib/search/basic")) {
    return true;
  }

  // トップページのヘッダにある「基本検索」リンクをクリック
  const nav = page
    .waitForNavigation({ waitUntil: "domcontentloaded", timeout: 30000 })
    .catch(() => null);

  const clicked = await page
    .evaluate(() => {
      const links = Array.from(document.querySelectorAll("a"));
      for (const a of links) {
        if ((a.innerText || "").trim() === "基本検索") {
          a.click();
          return true;
        }
      }
      return false;
    })
    .catch(() => false);

  if (clicked) {
    await nav;
    await new Promise((r) => setTimeout(r, 1000));
    return true;
  }

  return false;
}

// 検索フォームに検索語を入力して送信する。
// 検索ページ (#sword) が表示されるのを待ってから操作する。
async function submitSearch(page, query) {
  // 検索ページへ移動する
  const ok = await goToSearchPage(page);
  if (!ok) {
    throw new Error("could not reach search page");
  }

  // 検索フォームが現れるまで待つ
  const sword = await page.waitForSelector("#sword", { timeout: 30000 });
  if (!sword) {
    throw new Error("search form (#sword) not found");
  }

  await page.type("#sword", query, { delay: 10 });

  // waitForNavigation を先に立ててからフォーム送信する
  const nav = page
    .waitForNavigation({ waitUntil: "domcontentloaded", timeout: 30000 })
    .catch(() => null);

  await page.evaluate(() => {
    const form = document.querySelector("form");
    if (!form) {
      return;
    }
    const btn = form.querySelector(
      'button[type="submit"], input[type="submit"]'
    );
    if (btn) {
      btn.click();
    } else {
      form.submit();
    }
  });

  await nav;

  // 結果ページが安定するまで待つ
  await new Promise((r) => setTimeout(r, 1500));
}

// 検索結果ページから結果を収集する。
async function collectResults(page, query) {
  // 検索は時間がかかる場合があるので、結果リンク or 「0 件」表示が
  // 現れるまで最大 60 秒ポーリングで待つ。ページ遷移中 (detached frame) の
  // 失敗もリトライで吸収する。
  const deadline = Date.now() + 60000;
  let ready = false;
  while (Date.now() < deadline) {
    try {
      ready = await page.evaluate(() => {
        const hasLinks = Array.from(document.querySelectorAll("a")).some(
          (a) => a.href && a.href.includes("/lib/link/")
        );
        const zero = /0\s*件/.test(
          document.body ? document.body.innerText : ""
        );
        const loading = /(検索中|Loading)/.test(
          document.body ? document.body.innerText : ""
        );
        return (hasLinks || zero) && !loading;
      });
      if (ready) {
        break;
      }
    } catch (e) {
      // detached frame など: ページ遷移中なので待つ
    }
    await new Promise((r) => setTimeout(r, 1000));
  }

  if (!ready) {
    // 最後にもう一度、結果ページかどうか確認 (0件も含む)
  }

  const data = await page.evaluate(() => {
    const links = Array.from(document.querySelectorAll("a"))
      .filter((a) => a.href && a.href.includes("/lib/link/"))
      .map((a) => {
        // 各結果行は <a> 内にクラス付き div で構成される:
        //   .headword  見出し (例: "1. 実験")
        //   .titleId   辞書名 (例: "日本大百科全書")
        //   .snippet   限定的な意味 (スニペット)
        const headword = a.querySelector(".headword");
        const titleId = a.querySelector(".titleId");
        const snippet = a.querySelector(".snippet");
        return {
          headword: (headword ? headword.innerText : "").replace(/\s+/g, " ").trim(),
          titleId: (titleId ? titleId.innerText : "").replace(/\s+/g, " ").trim(),
          snippet: (snippet ? snippet.innerText : "").replace(/\s+/g, " ").trim(),
          href: a.href,
        };
      });

    // 見出しの先頭「N. 」を除去
    const results = links.map((l) => {
      const title = l.headword.replace(/^\d+\.\s*/, "");
      return {
        title,
        dict: l.titleId,
        snippet: l.snippet,
        url: l.href,
      };
    });

    // 件数 (例: 「706 件」)
    const totalMatch = document.body.innerText.match(/(\d[\d,]*)\s*件/);
    const total = totalMatch ? totalMatch[1] : 0;

    return { results, total };
  });

  // 完全一致: 見出しが検索語そのもの、または【見出し】内が検索語と一致する項目
  // 例: 実験 / じっ‐けん【実験】 / 【実験】じっけん は完全一致。
  //     実験心理学 は部分一致なので除外。
  const exact = data.results.filter((r) => {
    const t = r.title;
    // 【】内の見出しを抽出
    const bracket = t.match(/【([^】]+)】/);
    const bracketText = bracket ? bracket[1] : "";
    // 見出しそのもの or 【】内が一致
    return t === query || bracketText === query;
  });

  // 結果 URL をリダイレクタ経由に変換
  const wrap = (r) => ({ ...r, url: redirectorUrl(r.url) });

  return {
    total: data.total,
    exact: exact.map(wrap),
    results: data.results.map(wrap),
  };
}

// ---------------------------------------------------------------------------
// メイン
// ---------------------------------------------------------------------------

// 常駐 Chrome の新しいタブで URL を開く。
// CDP の /json/new エンドポイントに PUT を送る。
async function openTabs(urls) {
  for (const url of urls) {
    try {
      await fetch(`${CDP}/json/new?${encodeURIComponent(url)}`, {
        method: "PUT",
        signal: AbortSignal.timeout(10000),
      });
    } catch (e) {
      // 1つ失敗しても続行
    }
    await new Promise((r) => setTimeout(r, 500));
  }
}

async function main() {
  const query = process.argv[2];
  if (!query) {
    console.log(result("error", { message: "no query" }));
    process.exit(1);
  }

  // --fetch モード: 指定 URL の意味全文を取得して返す。
  // 戻り値: { status, title, dict, text }
  if (query === "--fetch") {
    const url = process.argv[3];
    if (!url) {
      console.log(result("error", { message: "no url" }));
      process.exit(1);
    }
    const conn = await connectOrLaunch().catch(() => null);
    if (!conn) {
      console.log(result("error", { message: "chrome not available" }));
      process.exit(1);
    }
    let browser = conn.browser;
    let chrome = conn.chrome;
    let existing = conn.existing;
    try {
      const page = await browser.newPage();
      await page.setUserAgent(UA);
      await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45000 }).catch(() => {});
      // リダイレクタ -> proxy の遷移と本文描画 (#main) を待ってから取得する
      await page.waitForSelector("#main", { timeout: 15000 }).catch(() => {});
      await new Promise((r) => setTimeout(r, 1000));
      const data = await page
        .evaluate(() => {
          const main = document.querySelector("#main");
          const text = main
            ? main.innerText.replace(/\s+/g, "\n").replace(/\n{3,}/g, "\n\n").trim()
            : document.body.innerText.trim();
          return { title: document.title || "", text: text.slice(0, 4000) };
        })
        .catch(() => ({ title: "", text: "" }));
      console.log(result("ok", { title: data.title, text: data.text }));
    } catch (e) {
      console.log(result("error", { message: e.message }));
    }
    await cleanup(browser, chrome, existing);
    process.exit(0);
  }

  // --open-tabs モード: 指定 URL を常駐 Chrome のタブで開く
  if (query === "--open-tabs") {
    const urls = process.argv.slice(3);
    if (urls.length === 0) {
      console.log(result("error", { message: "no urls" }));
      process.exit(1);
    }
    const conn = await connectOrLaunch().catch(() => null);
    if (!conn) {
      console.log(result("error", { message: "chrome not available" }));
      process.exit(1);
    }
    await openTabs(urls);
    await cleanup(conn.browser, conn.chrome, conn.existing);
    console.log(result("ok", { status: "tabs_opened", count: urls.length }));
    process.exit(0);
  }

  // --init モード: Chrome を起動してセッションを初期化する (先回りのウォームアップ)。
  // 常駐させるため Chrome は終了しない (ログインが必要なら開いたままにする)。
  // 戻り値: { status: "ok", state: "ready"|"auth"|"full" }
  if (query === "--init") {
    requireInstitutionConfig();
    const conn = await connectOrLaunch().catch(() => null);
    if (!conn) {
      console.log(result("error", { message: "chrome not available" }));
      process.exit(1);
    }
    try {
      const page = await conn.browser.newPage();
      await preparePage(page);
      await gotoEntry(page);
      const state = await judgePageState(page);
      await page.close().catch(() => {});
      console.log(result("ok", { state }));
    } catch (e) {
      console.log(result("error", { message: e.message }));
    }
    // Chrome は常駐させる
    await conn.browser.disconnect().catch(() => {});
    process.exit(0);
  }

  let browser;
  let chrome = null;
  let existing = false;

  try {
    requireInstitutionConfig();

    // 1. Chrome に接続 (なければ起動)
    const conn = await connectOrLaunch();
    browser = conn.browser;
    chrome = conn.chrome;
    existing = conn.existing;

    // 2. 新規ページを開く
    const page = await browser.newPage();
    await preparePage(page);

    // 3. リダイレクタ経由でトップページへ遷移
    const nav = await gotoEntry(page);
    if (!nav.ok) {
      console.log(result("error", { message: "navigation failed" }));
      await cleanup(browser, chrome, existing);
      return;
    }

    // 4. ページ状態を判定
    const state = await judgePageState(page);
    if (state === "auth") {
      console.log(
        result("auth", { title: await page.title(), url: page.url() })
      );
      await cleanup(browser, chrome, existing);
      return;
    }
    if (state === "full") {
      console.log(
        result("full", { title: await page.title(), url: page.url() })
      );
      await cleanup(browser, chrome, existing);
      return;
    }

    // 5. ログイン状態を確認。未ログインなら auth を返す
    const login = await ensureLoggedIn(page);
    if (login.needsLogin || !login.loggedIn) {
      console.log(
        result("auth", { title: await page.title(), url: page.url() })
      );
      await cleanup(browser, chrome, existing);
      return;
    }

    // 6. 検索フォームに入力して送信
    await submitSearch(page, query);

    // 7. 結果を収集
    const collected = await collectResults(page, query);

    console.log(
      result("ok", {
        query,
        total: collected.total,
        exact: collected.exact,
        results: collected.results,
      })
    );

    await cleanup(browser, chrome, existing);
  } catch (e) {
    console.log(result("error", { message: e.message }));
    await cleanup(browser, chrome, existing);
    process.exit(1);
  }
}

main();
