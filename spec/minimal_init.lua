--- Run this file before unittests.
--- 依存プラグインはないので、runtimepath の設定のみ行う。

vim.opt.rtp:append(".")

vim.cmd("runtime plugin/refsearch.vim")
