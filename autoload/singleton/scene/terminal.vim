let s:scene = {}

function singleton#scene#terminal#get() abort
  return s:scene
endfunction

function s:scene.is_available() abort
  return has('unix')
endfunction

function s:scene.is_master() abort
  return $VIM_TERMINAL is# '' ||
  \   s:call('group', []) isnot# g:singleton#group
endfunction

function s:scene.call_action(action, args) abort
  let result = s:call(a:action, a:args)

  if result is# 'delay'
    if !has('gui_running')
      echo 'Opening by remote Vim...'
      echo 'cancel to <C-c>'
    endif
    let result = s:receive_from_parent()
    if result is# 'cancel'
      echo 'Cancelled.  Starting up Vim...'
      call s:call(['cancel', []])
    endif
  endif

  if result is# 'ok'
    set viminfo=  " Don't save viminfo.
    quitall!
  endif

  " TODO: show error
endfunction

function s:call(action, args) abort
  let call_args = [a:action, a:args]
  let message = json_encode(['call', 'Tapi_singleton_receive', call_args])
  let message = substitute(message, '!', '\\u0021', 'g')
  let message = substitute(message, '#', '\\u0023', 'g')
  let message = substitute(message, '%', '\\u0025', 'g')
  let message = escape(message, '"')
  silent execute '!echo -e "\e]51;' . message . '\x07"'
  return s:receive_from_parent()
endfunction

function s:receive_from_parent() abort
  let message = []
  while 1
    let ch = singleton#_getchar()
    if ch is# "\<C-c>"
      return 'cancel'
    elseif ch is# "\n"
      break
    else
      call add(message, ch)
    endif
  endwhile
  return json_decode(join(message, ''))
endfunction


" server side

function Tapi_singleton_receive(bufnr, args) abort
  let [action, args] = a:args
  let caller = {
  \   'scene': 'terminal',
  \   'id': a:bufnr,
  \   'callback': function('s:send_to_term', [a:bufnr]),
  \ }
  let result = singleton#action#do(action, args, caller)
  call caller.callback(result)
endfunction

function s:send_to_term(bufnr, data) abort
  call term_sendkeys(a:bufnr, json_encode(a:data) . "\n")
endfunction
