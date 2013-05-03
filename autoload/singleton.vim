" Uses Vim with singleton.
" Version: 1.1
" Author : thinca <thinca+vim@gmail.com>
" License: zlib License

let s:save_cpo = &cpo
set cpo&vim

function! s:def(var, val)
  if !exists(a:var)
    let {a:var} = a:val
  endif
endfunction

call s:def('g:singleton#ignore_pattern', {})
call s:def('g:singleton#entrust_pattern', {
\   'svn': [
\     '/svn-\%(commit\|prop\)\%(\.\d\+\)\?\.tmp$',
\     '/\.svn/tmp/.*\.tmp$',
\   ],
\   'git': [
\     '/\.git/\%(modules/.\+/\)\?COMMIT_EDITMSG$',
\     '/\.git/rebase-merge/.*$',
\     '/\.git/.*\.diff$',
\   ],
\   'hg': '/hg-editor-.\{6}\.txt$',
\   'bar': '/bzr_log\..\{6}$',
\ })
call s:def('g:singleton#group', $USER . $USERNAME)
call s:def('g:singleton#opener', 'tab drop')
call s:def('g:singleton#treat_stdin', 1)
call s:def('g:singleton#disable', 0)

let s:data_count = get(s:, 'data_count', 1)
let s:master = get(s:, 'master', 0)

let s:entrust_clients = {}

function! singleton#enable(...)
  if !has('vim_starting') || g:singleton#disable
    return
  endif
  if !has('clientserver')
    throw 'singleton: This plugin requires +clientserver feature.'
  endif

  " Avoid starting with multiple Vim instances.
  call s:set_leave()
  if singleton#get_master() ==# ''
    let s:master = 1
    return
  endif

  " Stdin(:help --) support.
  let c = argc()
  if g:singleton#treat_stdin && c == 0
    augroup plugin-singleton-stdin
      autocmd! StdinReadPost *
      \        call singleton#send('stdin', ['[stdin]', getline(1, '$')])
    augroup END
    return
  endif

  " FIXME: A path that doesn't exist can not expand to fullpath.
  let files = map(argv(), 'fnamemodify(v:val, ":p")')

  " Diff mode support.
  if &diff && c <= 2
    call singleton#send('diff', [files])
    return
  endif

  " Remote edit support.
  let pattern = s:to_pattern(g:singleton#entrust_pattern)
  if c == 1 && s:path(files[0]) =~? pattern
    call singleton#send('entrust', [files[0]])
    return
  endif

  let pattern = s:to_pattern(g:singleton#ignore_pattern)
  if pattern !=# ''
    call filter(files, 's:path(v:val) !~? pattern')
  endif
  if !empty(files)
    call singleton#send('file', [files])
  endif
endfunction

function! singleton#is_master()
  return 0 < s:master
endfunction

function! singleton#get_master()
  let master = get(filter(s:serverlist(),
  \            'remote_expr(v:val, "singleton#is_master()")'), 0, '')
  return master
endfunction

function! singleton#set_master(...)
  let server = ''
  let val = 1
  for arg in a:000
    if type(arg) == type('')
      let server = arg
    elseif type(arg) == type(0)
      let val = arg
    endif
    unlet arg
  endfor

  if server !=# ''
    return remote_expr(server, printf('singleton#set_master(%d)', val))
  endif

  if 0 < val
    if v:servername !=# '' && s:master == 0
      let master = singleton#get_master()
      if master ==# '' || remote_expr(master, 'singleton#set_master(0)')
        let s:master = 1
        return 1
      endif
    endif
  else
    let s:master = val
    return 1
  endif
  return 0
endfunction

function! singleton#send(action, args)
  let server = singleton#get_master()
  if server ==# ''
    return
  endif

  augroup plugin-singleton-wait
    autocmd! RemoteReply * call s:replied(expand('<amatch>'))
  augroup END
  set viminfo=  " Don't save viminfo.

  try
    call remote_foreground(server)
  catch
  endtry

  let expr = printf('singleton#receive(%s, %s)',
  \                 string(a:action), string(a:args))
  call remote_expr(server, expr)

  if !has('gui_running')
    echo 'Opening by remote Vim...'
    echo 'cancel to <C-c>'
  endif
  call s:wait()
  echo 'Cancelled.  Starting up Vim...'
  call remote_expr(server, 'singleton#receive("cancel", [])')
endfunction

function! s:replied(serverid)
  autocmd! plugin-singleton-wait
  let result = remote_read(a:serverid)
  if !has('gui_running')
    " echo result
  endif
  quitall!
endfunction

function! singleton#receive(cmd, args)
  let cliendid = expand('<client>')
  stopinsert
  let ret = call('s:action_' . a:cmd, a:args)
  if type(ret) == type('')
    call s:server2client(cliendid, ret)
  endif
  call foreground()
endfunction

function! s:action_file(files)
  for f in type(a:files) == type([]) ? a:files : [a:files]
    call s:open(f, 'file')
  endfor
  redraw
  return 'ok'
endfunction

function! s:action_entrust(file)
  call s:open(a:file, 'entrust')
  setlocal bufhidden=wipe
  let s:entrust_clients[bufnr('%')] = expand('<client>')
  augroup plugin-singleton-reply
    autocmd! BufWipeout <buffer> call s:finish_edit(expand('<abuf>'))
  augroup END
  redraw
endfunction

function! s:finish_edit(bufnr)
  if has_key(s:entrust_clients, a:bufnr)
    let client_id = remove(s:entrust_clients, a:bufnr)
    call s:server2client(client_id, 'ok')
  endif
endfunction

function! s:action_diff(files)
  if type(a:files) != type([]) || len(a:files) < 2 || 3 < len(a:files)
    throw 'singleton: Invalid argument for diff(): ' . string(a:files)
  endif

  let files = map(copy(a:files), 'fnamemodify(v:val, ":p")')
  call s:open(files[0], 'diff')
  diffthis
  for f in files[1 :]
    rightbelow vsplit `=f`
    diffthis
  endfor
  " windo diffthis
  1 wincmd w
  return 'ok'
endfunction

function! s:action_stdin(name, data)
  let name = a:name . '@' . s:data_count
  let s:data_count += 1
  call s:open(name, 'stdin')
  silent put =a:data
  silent 1 delete _
  setlocal readonly nomodified buftype=nofile
  filetype detect
  redraw
  return 'ok'
endfunction

function! s:action_cancel()
  " XXX: Don't support multi client.
  autocmd! plugin-singleton-reply
  echohl WarningMsg
  echomsg 'singleton: Operation cancelled from client.'
  echohl None
endfunction

function! s:wait()
  let c = ''
  try
    while c !=# "\<C-c>"
      let c = getchar()
      if type(c) == type(0)
        let c = nr2char(c)
      endif
    endwhile
  catch '^Vim:Interrupt'
  endtry
endfunction

function! s:to_pattern(pat)
  if type(a:pat) == type('')
    return a:pat
  elseif type(a:pat) == type([])
    return join(map(a:pat, 's:to_pattern(v:val)'), '\m\|')
  elseif type(a:pat) == type({})
    return s:to_pattern(values(a:pat))
  endif
  return ''
endfunction

function! s:bufopened(file)
  let f = fnamemodify(a:file, ':p')
  for tabnr in range(1, tabpagenr('$'))
    for nbuf in tabpagebuflist(tabnr)
      if f ==# fnamemodify(bufname(nbuf), ':p')
        return 1
      endif
    endfor
  endfor
  return 0
endfunction

function! s:open(file, type)
  if exists('g:singleton#opener_' . a:type)
    let opener = g:singleton#opener_{a:type}
  else
    let opener = g:singleton#opener
  endif
  let openfile = fnamemodify(a:file, ':p')
  execute opener '`=openfile`'
endfunction

function! s:path(path)
  return simplify(substitute(a:path, '\\', '/', 'g'))
endfunction

function! s:server2client(clientid, string)
  try
    return server2client(a:clientid, a:string)
  catch
    echohl ErrorMsg
    echomsg matchstr(v:exception, '^Vim(.\{-}):\zs.*')
    echohl None
  endtry
endfunction

function! s:serverlist()
  return filter(split(serverlist(), "\n"), 's:check_id(v:val)')
endfunction

function! s:check_id(server)
  try
    return remote_expr(a:server, 'g:singleton#group') ==# g:singleton#group
  catch
  endtry
  return 0
endfunction

function! s:set_leave()
  augroup plugin-singleton-leave
    autocmd! VimLeave * call s:on_leave()
  augroup END
endfunction

function! s:on_leave()
  if singleton#is_master()
    for s in s:serverlist()
      if remote_expr(s, 'singleton#set_master(1)')
        return
      endif
    endfor
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
