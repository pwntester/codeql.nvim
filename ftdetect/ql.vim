au BufRead,BufNewFile *.ql  setfiletype ql
au BufRead,BufNewFile *.qll setfiletype ql

nnoremap qr :RunQuery<CR>
nnoremap qp :QuickEvalPredicate<CR>
nnoremap qe :QuickEval<CR>
vnoremap qe :QuickEval<CR>
