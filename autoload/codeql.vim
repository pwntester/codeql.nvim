let s:database = ''
let s:metadata = {}
let s:history = []

function! codeql#extractQueryMetadata(query)
    " TODO: support multi-line properties
    let l:metadata = {}
    for l:line in readfile(a:query, '', 20)
        let l:propIdx = match(l:line, '@[^ ]\+')
        if l:propIdx > 0
            let l:prop = matchstr(l:line, '@[^ ]\+')
            let l:value = l:line[l:propIdx+len(l:prop)+1:]
            let l:metadata[l:prop[1:]] = l:value
        endif
    endfor
    return l:metadata
endfunction

function! codeql#runQuery(database, query) abort
    let s:database = fnamemodify(a:database, ':p')
    let s:metadata = codeql#extractQueryMetadata(a:query)

    if !isdirectory(s:database)
        call codeql#panel#printToTestPanel('Incorrect database')
        return
    endif

    if a:query == '%'
        let l:query = expand('%:p')'
    else
        let l:query = a:query
    endif

    let l:bqrs = tempname()
    let l:results = tempname()

    call codeql#panel#openTestPanel()
    call codeql#panel#clearTestPanel()

    let search_path = ''
    if exists('g:codeql_search_path')
        let search_path = "--search-path "
        for path in g:codeql_search_path
            let search_path.=path.':'
        endfor
    endif

    if !isdirectory(s:database.'/src') && filereadable(s:database.'/src.zip')
        call codeql#job#runCommands([
            \ ['mkdir', s:database.'/src', ';', 'unzip', s:database.'/src.zip', '-d', s:database.'/src'],
            \ ['codeql', 'query', 'run', search_path, '-o='.l:bqrs, '-d='.s:database, l:query],
            \ ['codeql', 'bqrs', 'decode', '-o='.l:results, '--format=json', '--entities=string,url', l:bqrs],
            \ ['process_results', l:results, s:database, l:query]
        \ ])
    else
        call codeql#job#runCommands([
            \ ['codeql', 'query', 'run', search_path, '-o='.l:bqrs, '-d='.s:database, l:query],
            \ ['codeql', 'bqrs', 'decode', '-o='.l:results, '--format=json', '--entities=string,url', l:bqrs],
            \ ['process_results', l:results, s:database, l:query]
        \ ])
    endif
endfunction

function! codeql#show_results(file, database, query, history) abort
    if !filereadable(a:file) | return | endif
    let l:json_file = join(readfile(a:file))
    let l:results = json_decode(l:json_file)

    if !has_key(l:results, '#select')
        call codeql#panel#printToTestPanel('No results')
        if a:history == 0
            call s:save_session(a:file, a:database, 0, a:query)
            return
        endif
    endif


    let l:issues = []

    " path query
    if has_key(s:metadata, 'kind') && s:metadata['kind'] == 'path-problem' && 
     \ has_key(l:results, 'edges') && has_key(l:results, 'nodes') && has_key(l:results, '#select')
        let l:tuples = l:results['#select']['tuples']
        let l:edges = l:results['edges']['tuples']
        let l:nodes = l:results['nodes']['tuples']

        " dedup
        let l:nodes = filter(copy(l:nodes), 'index(l:nodes, v:val, v:key+1)==-1')
        let l:edges = filter(copy(l:edges), 'index(l:edges, v:val, v:key+1)==-1')
        
        call codeql#panel#printToTestPanel(' ')
        call codeql#panel#printToTestPanel('Query Metadata:')

        for [prop, value] in items(s:metadata)
            call codeql#panel#printToTestPanel(l:prop.': '.l:value)
        endfor

        call codeql#panel#printToTestPanel('Number of results: '.len(l:tuples))
        for l:tuple in l:tuples

            " TODO: In VSCode, reference node is only used for issue level,
            " not shown as node
            let l:reference = l:tuple[0]
            let l:reference_filename = s:uri_to_fname(l:reference['url']['uri'])
            let l:reference_line = l:reference['url']['startLine']
            let l:reference_node = {
                \ 'label': l:reference['label'],
                \ 'mark': '★',
                \ 'filename': l:reference_filename,
                \ 'line': l:reference_line,
                \ 'visitable': !empty(l:reference_filename) && filereadable(l:reference_filename)? v:true : v:false,
                \ 'orig': l:reference
                \ }

            let l:source = l:tuple[1]
            let l:source_filename = s:uri_to_fname(l:source['url']['uri'])
            let l:source_line = l:source['url']['startLine']
            let l:source_node = {
                \ 'label': l:source['label'],
                \ 'mark': '⭃',
                \ 'filename': l:source_filename,
                \ 'line': l:source_line,
                \ 'visitable': !empty(l:source_filename) && filereadable(l:source_filename)? v:true : v:false,
                \ 'orig': l:source
                \ }

            let l:sink = l:tuple[2]
            let l:sink_filename = s:uri_to_fname(l:sink['url']['uri'])
            let l:sink_line = l:sink['url']['startLine']
            let l:sink_node = {
                \ 'label': l:sink['label'],
                \ 'mark': '⦿',
                \ 'filename': l:sink_filename,
                \ 'line': l:sink_line,
                \ 'visitable': !empty(l:sink_filename) && filereadable(l:sink_filename)? v:true : v:false,
                \ 'orig': l:sink
                \ }

            let l:label = l:tuple[3]
            if len(l:tuple) > 4
                " Replace placeholders (ignore links)
                let l:extra = l:tuple[4:]
                let l:replacements = []
                for ex in l:extra
                    if type(ex) == v:t_string
                        call add(l:replacements, ex)
                    endif
                endfor
                call codeql#panel#printToTestPanel("replacements: " + len(l:replacements))
                let l:segments = split(l:label.' ', '$@')
                if len(l:segments) == len(l:replacements) + 1
                    let l:label = ''
                    for segment in l:segments
                        let l:label = l:label.l:segment.get(l:replacements, 0, '')
                        let l:replacements = l:replacements[1:]
                    endfor
                endif
            endif

            let l:label_node = {
                \ 'label': trim(l:label),
                \ 'mark': '≔',
                \ 'filename': v:null,
                \ 'line': v:null,
                \ 'visitable': v:false,
                \ 'orig': l:label
                \ }

            " will hold all paths found by expandDataflow
            let s:paths = []

            " initial path: label + source
            let l:path = [l:reference_node, l:label_node, l:source_node]

            " collect paths
            call codeql#expandDataflow(l:path, l:sink_node, l:edges)

            if len(s:paths) > 0
                " add issue paths to issues list
                call add(l:issues, {'is_folded': v:true, 'paths': s:paths, 'active_path': 0, 'type': 'path'})
            else 
                call codeql#panel#printToTestPanel("Failed to calculate dataflow")
            endif
        endfor

    " TODO: support string interpolation on `alert` queries?
    
    " raw query
    elseif has_key(l:results, '#select')
        call codeql#panel#printToTestPanel('Processing Raw Query results')

        let l:tuples = l:results['#select']['tuples']

        for l:tuple in l:tuples
            let l:path = []
            for l:element in l:tuple
                let l:node = {}
                if type(l:element) == v:t_dict
                    let l:filename = s:uri_to_fname(l:element['url']['uri'])
                    let l:line = l:element['url']['startLine']
                    let l:node = {
                        \ 'label': l:element['label'],
                        \ 'mark': '→',
                        \ 'filename': l:filename,
                        \ 'line': l:line,
                        \ 'visitable': !empty(l:filename) && filereadable(l:filename)? v:true : v:false,
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
            call add(l:issues, {'is_folded': v:true, 'paths': [l:path], 'active_path': 0, 'type': 'raw'})
        endfor
    endif

    if a:history == 0
        call s:save_session(a:file, a:database, len(l:issues), a:query)
    endif

    call codeql#panel#renderAuditPanel(a:database, s:metadata, l:issues)
endfunction

function! codeql#expandDataflow(path, sink_node, edges) abort
    let l:node = a:path[-1]

    let l:safe_net = 0
    while v:true
        " reached the sink?
        if l:node.orig == a:sink_node.orig
            let l:node['mark'] = '⦿'
            call add(a:path, l:node)
            call add(s:paths, a:path)
            return
        endif

        let l:nodes = codeql#getEdgeEnd(l:node, a:edges)
        if len(l:nodes) == 0
            " end vertice, discarding path 
            return
        elseif len(l:nodes) == 1
            let l:node = l:nodes[0]
            call add(a:path, l:node)
        elseif len(l:nodes) > 1
            " branch new path for every edge
            for l:branch_node in l:nodes
                " avoid infinite loops by not revisiting nodes
                if index(a:path, l:branch_node) == -1
                    let l:new_path = deepcopy(a:path)
                    call add(l:new_path, l:branch_node)
                    call codeql#expandDataflow(l:new_path, a:sink_node, a:edges)
                endif
            endfor

            " discard this path since new paths are created by expandDataflow
            return
        endif

        let l:safe_net += 1
        if l:safe_net == 100
            call codeql#panel#printToTestPanel("Aborting to prevent infinite loop")
            break
        endif
    endwhile
endfunction

function! codeql#getEdgeEnd(start_node, edges) abort
    let l:result = []
    for l:edge in a:edges
        if l:edge[0] == a:start_node.orig
            let l:end = l:edge[1]
            let l:end_filename = s:uri_to_fname(l:end['url']['uri']) 
            let l:end_line = l:end['url']['startLine']
            let l:end_node = {
                \ 'label': l:end.label,
                \ 'mark': '→',
                \ 'filename': l:end_filename,
                \ 'line': l:end_line,
                \ 'visitable': !empty(l:end_filename) && filereadable(l:end_filename)? v:true : v:false,
                \ 'orig': l:end
                \ }

            call add(l:result, l:end_node)
        endif
    endfor
    return l:result
endfunction

function! s:uri_to_fname(uri) abort
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
