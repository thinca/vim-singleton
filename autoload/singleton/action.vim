let s:data_count = get(s:, 'data_count', 1)
let s:entrust_callers = {}

function singleton#action#do(action, args, caller) abort
  stopinsert
  return call('s:action_' . a:action, a:args + [a:caller])
endfunction

function s:action_group(_caller) abort
  return g:singleton#group
endfunction

function s:action_file(files, caller) abort
  for f in type(a:files) is# v:t_list ? a:files : [a:files]
    call s:open(f, 'file', a:caller.scene)
  endfor
  redraw
  return 'ok'
endfunction

function s:action_entrust(file, caller) abort
  call s:open(a:file, 'entrust', a:caller.scene)
  setlocal bufhidden=wipe
  let s:entrust_callers[bufnr('%')] = a:caller
  augroup plugin-singleton-reply
    autocmd! BufWipeout <buffer> call s:finish_edit(expand('<abuf>'))
    autocmd! VimLeave * call s:finish_edit_all()
  augroup END
  redraw
  return 'delay'
endfunction

function s:finish_edit(bufnr) abort
  if has_key(s:entrust_callers, a:bufnr)
    let caller = remove(s:entrust_callers, a:bufnr)
    call caller.callback('ok')
  endif
endfunction

function s:finish_edit_all() abort
  for bufnr in keys(s:entrust_callers)
    call s:finish_edit(bufnr)
  endfor
endfunction

function s:action_diff(files, caller) abort
  if type(a:files) != type([]) || len(a:files) < 2 || 3 < len(a:files)
    throw 'singleton: Invalid argument for diff(): ' . string(a:files)
  endif

  let files = map(copy(a:files), 'fnamemodify(v:val, ":p")')
  call s:open(files[0], 'diff', a:caller.scene)
  diffthis
  for f in files[1 :]
    rightbelow vsplit `=f`
    diffthis
  endfor
  " windo diffthis
  1 wincmd w
  return 'ok'
endfunction

function s:action_stdin(data, caller) abort
  let name = '[stdin]' . '@' . s:data_count
  let s:data_count += 1
  call s:open(name, 'stdin', a:caller.scene)
  silent put =a:data
  silent 1 delete _
  setlocal readonly nomodified buftype=nofile
  filetype detect
  redraw
  return 'ok'
endfunction

function s:action_cancel(caller) abort
  let bufnr = s:find_buf_by_caller(a:caller)
  if bufnr
    let group = 'plugin-singleton-reply'
    execute printf('autocmd! %s BufWipeout <buffer=%d>', group, bufnr)
    call remove(s:entrust_callers, bufnr)
  endif
  echohl WarningMsg
  echomsg 'singleton: Operation cancelled from client.'
  echohl None
endfunction

function s:find_buf_by_caller(caller) abort
  for [bufnr, caller] in items(s:entrust_callers)
    if a:caller.scene is# caller.scene && a:caller.id is# caller.id
      return bufnr
    endif
  endfor
  return 0
endfunction

function s:open(file, type, scene) abort
  if exists('g:singleton#opener_' . a:scene . '_' . a:type)
    let opener = g:singleton#opener_{a:scene}_{a:type}
  elseif exists('g:singleton#opener_' . a:scene)
    let opener = g:singleton#opener_{a:scene}
  elseif exists('g:singleton#opener_' . a:type)
    let opener = g:singleton#opener_{a:type}
  else
    let opener = g:singleton#opener
  endif
  let openfile = fnamemodify(a:file, ':p')
  execute opener fnameescape(openfile)
endfunction
