if exists("g:loaded_refsearch")
  finish
endif
let g:loaded_refsearch = 1

" vim.g.refsearch_configuration を config.DATA にマージする。
" redirector / proxy は所属機関固有のため、ユーザー設定が必須。
lua require("refsearch.config").setup(vim.g.refsearch_configuration)

command! -nargs=* -bar RefSearch lua require("refsearch").command({ <f-args> })
command! -nargs=0 -bar -bang RefSearchInit lua require("refsearch").init({ visible = <bang>1 })
