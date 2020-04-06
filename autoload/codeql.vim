let s:database = ''
let s:history = []

function! codeql#extractQueryMetadata(query)
    let l:metadata = system('codeql resolve metadata --format=json '.a:query)
    return json_decode(l:metadata)
endfunction

function! codeql#setDatabase(database) abort
    let s:database = fnamemodify(a:database, ':p')
    if !isdirectory(s:database)
        "call codeql#panel#printToTestPanel('Incorrect database')
        echom 'Incorrect database'
        return
    endif
endfunction

function! codeql#runQuery(quick_eval) abort
    if s:database == ''
        "call codeql#panel#printToTestPanel('Missing database. Use SetDatabase command')
        echom 'Missing database. Use SetDatabase command'
        return
    endif

    if !isdirectory(s:database.'/src') && filereadable(s:database.'/src.zip')
        execute '!mkdir'.s:database.'/src'
        execute 'unzip'.s:database.'/src.zip -d '.s:database.'/src'
    endif

    " TODO: support visual ranges 
 
    let l:queryPath = expand('%:p')

	" [bufnum, lnum, col, off, curswant] ~
    if mode() == "v" || mode() == "V" || mode() == "\<C-V>"
        let [line_start, column_start] = getpos("'<")[1:2]
        let [line_end, column_end] = getpos("'>")[1:2]
        let column_end = column_end == 2147483647 ? len(getline(line_end)) : column_end
    else
        let [line_start, column_start] = getcurpos()[1:2]
        let [line_end, column_end] = getcurpos()[1:2]
    endif

    "echom "Quickeval at: ".line_start."::".column_start."::".line_end."::".column_end
    
    let l:config = {
        \ 'quick_eval': a:quick_eval,
        \ 'buf': nvim_get_current_buf(),
        \ 'query': l:queryPath,
        \ 'db': s:database,
        \ 'startLine': line_start,
        \ 'startColumn': column_start,
        \ 'endLine': line_end,
        \ 'endColumn': column_end,
        \ 'metadata': codeql#extractQueryMetadata(l:queryPath),
        \ }
    let res = luaeval("require('ql.queryserver').run_query(_A)", l:config)

endfunction

function! codeql#loadJsonResults(file) abort
    if !filereadable(a:file) | return | endif
    let l:json_file = join(readfile(a:file))
    let l:results = json_decode(l:json_file)

    if !has_key(l:results, '#select')
        " call codeql#panel#printToTestPanel('No results')
        echom 'No results'
        " if a:history == 0
        "     call s:save_session(a:file, a:database, 0, a:query)
        "     return
        " endif
    endif

    let l:issues = []

    " TODO: support string interpolation on `alert` queries?
    " raw query
 
    if has_key(l:results, '#select')
        " call codeql#panel#printToTestPanel('Processing Raw Query results')

        let l:tuples = l:results['#select']['tuples']

        for l:tuple in l:tuples
            let l:path = []
            for l:element in l:tuple
                let l:node = {}
                if type(l:element) == v:t_dict && has_key(l:element, 'url')
                    let l:filename = codeql#uriToFname(l:element['url']['uri'])
                    let l:line = l:element['url']['startLine']
                    let l:node = {
                        \ 'label': l:element['label'],
                        \ 'mark': '→',
                        \ 'filename': l:filename,
                        \ 'line': l:line,
                        \ 'visitable': !empty(l:filename) && filereadable(l:filename)? v:true : v:false,
                        \ 'orig': l:element
                        \ }
                elseif type(l:element) == v:t_dict && !has_key(l:element, 'url')
                    let l:node = {
                        \ 'label': l:element['label'],
                        \ 'mark': '≔',
                        \ 'filename': v:null,
                        \ 'line': v:null,
                        \ 'visitable': v:false,
                        \ 'orig': l:element
                        \ }
                elseif type(l:element) == v:t_string
                    let l:node = {
                        \ 'label': l:element,
                        \ 'mark': '≔',
                        \ 'filename': v:null,
                        \ 'line': v:null,
                        \ 'visitable': v:false,
                        \ 'orig': l:element
                        \ }
                else
                    let l:node = {
                        \ 'label': string(l:element),
                        \ 'mark': '≔',
                        \ 'filename': v:null,
                        \ 'line': v:null,
                        \ 'visitable': v:false,
                        \ 'orig': l:element
                        \ }
                endif
                call add(l:path, l:node)
            endfor

            " add issue paths to issues list
            call add(l:issues, {'is_folded': v:true, 'paths': [l:path], 'active_path': 0})
        endfor
    endif
    return l:issues

endfunction

function! codeql#uriToFname(uri) abort
    let l:colon = stridx(a:uri, ':')
    if l:colon == -1 | return a:uri | end
    let l:scheme = a:uri[0:l:colon]
    let l:path= a:uri[l:colon+1:]

    if a:uri[l:colon+1:l:colon+2] != '//'
        let l:orig_fname = v:lua.vim.uri_to_fname(l:scheme.'//'.l:path)
    else
        let l:orig_fname = v:lua.vim.uri_to_fname(a:uri)
    endif

    if isdirectory(s:database.'/src')
        return s:database.'/src'.l:orig_fname
    else
        return l:orig_fname
    endif
endfunction

function! s:save_session(file, database, issues, query) abort
    let l:dbname = split(a:database, '/')[-1:][0]
    let l:queryfile = fnamemodify(a:query, ':t') 
    call add(s:history, {
        \ 'file': a:file, 
        \ 'database': l:dbname, 
        \ 'epoch': localtime(), 
        \ 'time': strftime('%c'), 
        \ 'issues': a:issues,
        \ 'query': l:queryfile
        \ })
endfunction

function! codeql#show_history(element) abort
    if a:element < len(s:history)
        let l:version = s:history[a:element]
        call codeql#show_results(l:version['file'], l:version['database'], l:version['query'], 1)
    endif
endfunction

function! codeql#history() abort
    "let s:history = filter(s:history, 'isdirectory(v:val.database) && filereadable(v:val.file)')
	let l:options = map(copy(s:history), 'v:val.query." (".v:val.issues." results) (".v:val.time.") [".v:val.database."]"')
    if exists("*fzf#run")
        call fzf#run(fzf#wrap({
            \ 'source': map(deepcopy(l:options), {idx, item -> string(idx).'::'.item}),
            \ 'sink': function('codeql#show_history'),
            \ 'options': '+m --with-nth 2.. -d "::"',
            \ }))
    else
        let l:option = inputlist(['Select: '] + l:options)
        call codeql#show_history(l:option-1)
    endif
endfunction
