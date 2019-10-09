let s:scene = {}

function singleton#scene#remote#get() abort
  call s:scene.setup()
  return s:scene
endfunction

function s:scene.is_available() abort
  return has('clientserver') && v:servername isnot# ''
endfunction

function s:scene.setup() abort
  call s:set_leave_event()
  if singleton#scene#remote#get_master() ==# ''
    let s:master = 1
  endif
endfunction

function s:scene.is_master() abort
  return singleton#scene#remote#is_master()
endfunction

function s:scene.call_action(action, args) abort
  augroup plugin-singleton-remote-wait
    autocmd! RemoteReply * call s:replied(expand('<amatch>'))
  augroup END

  let target = singleton#scene#remote#get_master()

  let expr = printf('singleton#scene#remote#receive(%s, %s)',
  \                 string(a:action), string(a:args))
  let result = s:remote_expr(target, expr, 'error')

  if result is# 'delay'
    if !has('gui_running')
      echo 'Opening by remote Vim...'
      echo 'cancel to <C-c>'
    endif
    call s:wait()
    echo 'Cancelled.  Starting up Vim...'
    call s:remote_expr(target, 'singleton#scene#remote#receive("cancel", [])')
    let result = 'cancel'
  endif

  if result is# 'ok'
    set viminfo=  " Don't save viminfo.
    quitall!
  endif

  " TODO: Show error
endfunction



let s:master = get(s:, 'master', 0)

function singleton#scene#remote#is_master() abort
  return 0 < s:master
endfunction

function singleton#scene#remote#get_master() abort
  let master = get(filter(s:serverlist(),
  \   's:remote_expr(v:val, "singleton#scene#remote#is_master()", "")'), 0, '')
  return master
endfunction

function singleton#scene#remote#set_master(...) abort
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
    let expr = printf('singleton#scene#remote#set_master(%d)', val)
    return s:remote_expr(server, expr)
  endif

  if 0 < val
    if v:servername !=# '' && s:master == 0
      let master = singleton#scene#remote#get_master()
      if master ==# '' ||
      \   s:remote_expr(master, 'singleton#scene#remote#set_master(0)')
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

function s:replied(serverid) abort
  autocmd! plugin-singleton-remote-wait
  let result = remote_read(a:serverid)
  if result is# 'ok'
    set viminfo=  " Don't save viminfo.
    quitall!
  endif
  " Never reach, maybe
  if !has('gui_running')
    echo result
  endif
endfunction

function s:serverlist() abort
  return filter(split(serverlist(), "\n"), 's:check_id(v:val)')
endfunction

function s:check_id(server) abort
  return s:remote_expr(a:server, 'g:singleton#group') ==# g:singleton#group
endfunction

function s:remote_expr(server, expr, ...) abort
  let default = a:0 ? a:1 : 0
  try
    return remote_expr(a:server, a:expr)
  catch
  endtry
  return default
endfunction

function s:wait() abort
  let c = ''
  while c !=# "\<C-c>"
    let c = singleton#_getchar()
  endwhile
endfunction


function s:set_leave_event() abort
  augroup plugin-singleton-remote-leave
    autocmd! VimLeave * call s:on_leave()
  augroup END
endfunction

function s:on_leave() abort
  if singleton#scene#remote#is_master()
    for s in s:serverlist()
      if s:remote_expr(s, 'singleton#scene#remote#set_master(1)')
        return
      endif
    endfor
  endif
endfunction


" server side

function singleton#scene#remote#receive(cmd, args) abort
  let clientid = expand('<client>')
  let caller = {
  \   'scene': 'remote',
  \   'id': clientid,
  \   'callback': function('s:server2client', [clientid])
  \ }
  let result = singleton#action#do(a:cmd, a:args, caller)
  call foreground()
  return result
endfunction

function s:server2client(clientid, string) abort
  try
    return server2client(a:clientid, a:string)
  catch
    echohl ErrorMsg
    echomsg matchstr(v:exception, '^Vim(.\{-}):\zs.*')
    echohl None
  endtry
endfunction
