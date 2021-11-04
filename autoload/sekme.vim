let s:is_tab_map = v:false

function! s:is_previous_character_space(col, line) abort
    return !a:col || a:line[a:col - 1]  =~ '\s'
endfunction

function! s:is_previous_character_abbvr_char(col, line) abort
    return a:col && a:line[a:col - 1]  =~ g:sekme_abbvr_trigger_char
endfunction

function sekme#completion_wrapper(backward) abort
    if pumvisible()
        return a:backward ? "\<C-p>" : "\<C-n>"
    endif

    let l:col = col('.') - 1
    let l:line = getline('.')
    if !a:backward && s:is_previous_character_abbvr_char(l:col, l:line)
        return "\<C-]>"
    endif

    if s:is_tab_map && s:is_previous_character_space(l:col, l:line)
        if a:backward
            return "\<S-TAB>"
        else
            return "\<TAB>"
        endif
    endif

    lua require'sekme'.trigger_completion()
    return ''
endfunction

function sekme#setup_keymap() abort
    let s:is_tab_map = tolower(g:sekme_completion_key) == "<tab>"

    execute 'imap <nowait> ' . g:sekme_completion_key . ' <plug>(SekmeCompleteFwd)'
    execute 'imap <nowait> ' . g:sekme_completion_rkey . ' <plug>(SekmeCompleteBack)'
endfunction
