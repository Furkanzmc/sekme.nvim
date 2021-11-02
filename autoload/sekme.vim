function! s:is_previous_character_space() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~ '\s'
endfunction

function! s:is_previous_character_abbvr_char() abort
    let col = col('.') - 1
    return col && getline('.')[col - 1]  =~ g:sekme_abbvr_trigger_char
endfunction

function sekme#completion_wrapper()
    lua require'sekme'.trigger_completion()
    return ''
endfunction

function s:trigger_completion()
    return "\<c-r>=sekme#completion_wrapper()\<CR>"
endfunction

function sekme#setup_keymap()
    execute 'imap <silent><expr> ' . g:sekme_completion_key .
                \ ' pumvisible() ? "\<C-n>" : <SID>is_previous_character_abbvr_char() ? "\<C-]>" : <SID>is_previous_character_space() ? "\<TAB>" : <SID>trigger_completion()'

    execute 'imap <silent><expr> ' . g:sekme_completion_rkey .
                \ 'pumvisible() ? "\<C-p>" : <SID>is_previous_character_space() ? "\<S-TAB>" : <SID>trigger_completion()'
endfunction
