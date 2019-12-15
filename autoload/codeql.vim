let s:database = ''

function! codeql#runQuery(database, query) abort
    let s:database = fnamemodify(a:database, ':p')

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

    if !isdirectory(s:database.'/src') && filereadable(s:database.'/src.zip')
        call codeql#job#runCommands([
            \ ['mkdir', s:database.'/src', ';', 'unzip', s:database.'/src.zip', '-d', s:database.'/src'],
            \ ['codeql', 'query', 'run', '-o='.l:bqrs, '-d='.s:database, l:query],
            \ ['codeql', 'bqrs', 'decode', '-o='.l:results, '--format=json', '--entities=string,url', l:bqrs],
            \ ['process_results', l:results]
        \ ])
    else
        call codeql#job#runCommands([
            \ ['codeql', 'query', 'run', '-o='.l:bqrs, '-d='.s:database, l:query],
            \ ['codeql', 'bqrs', 'decode', '-o='.l:results, '--format=json', '--entities=string,url', l:bqrs],
            \ ['process_results', l:results]
        \ ])
    endif
endfunction

function! codeql#process_results(file) abort
    if !filereadable(a:file) | return | endif
    let l:json_file = join(readfile(a:file))
    let l:results = json_decode(l:json_file)

    if !has_key(l:results, '#select')
        call codeql#panel#printToTestPanel('No results')
        return
    endif

    let l:issues = []

    " path query
    if has_key(l:results, 'edges') && has_key(l:results, 'nodes') && has_key(l:results, '#select')
        call codeql#panel#printToTestPanel('Processing Path Query results')

        let l:tuples = l:results['#select']['tuples']
        let l:edges = l:results['edges']['tuples']
        let l:nodes = l:results['nodes']['tuples']

        " dedup
        let l:nodes = filter(copy(l:nodes), 'index(l:nodes, v:val, v:key+1)==-1')
        let l:edges = filter(copy(l:edges), 'index(l:edges, v:val, v:key+1)==-1')
        
        call codeql#panel#printToTestPanel("Number of results: ".len(l:tuples))
        for l:tuple in l:tuples

            if len(l:tuple) != 4
                call codeql#panel#printToTestPanel('Incorrect number of columns for path query')
                return
            endif

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
            let l:label_node = {
                \ 'label': l:label,
                \ 'mark': '≔',
                \ 'filename': v:null,
                \ 'line': v:null,
                \ 'visitable': v:false,
                \ 'orig': l:label
                \ }

            " will hold all paths found by expandDataflow
            let s:paths = []

            " initial path: label + source
            let l:path = [l:label_node, l:source_node]

            " collect paths
            call codeql#panel#printToTestPanel("Processing Dataflow")
            call codeql#expandDataflow(l:path, l:sink_node, l:edges)

            if len(s:paths) > 0
                " add issue paths to issues list
                call add(l:issues, {'is_folded': v:true, 'paths': s:paths, 'active_path': 0, 'type': 'path'})
            else 
                call codeql#panel#printToTestPanel("Failed to calculate dataflow")
            endif

        endfor

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
    call codeql#panel#renderAuditPanel(s:database, l:issues)
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
