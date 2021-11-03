imap <silent> <expr> <plug>(SekmeCompleteFwd) pumvisible() ? "\<C-n>" : sekme#completion_wrapper(v:false)
imap <silent> <expr> <plug>(SekmeCompleteBack) pumvisible() ? "\<C-p>" : sekme#completion_wrapper(v:true)
