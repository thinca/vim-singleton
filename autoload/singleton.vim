" Uses Vim with singleton.
" Version: 1.1
" Author : thinca <thinca+vim@gmail.com>
" License: zlib License

function s:def(var, val) abort
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
\     '/\.git/modules/',
\     '/\.git/\%(modules/.\+/\)\?COMMIT_EDITMSG$',
\     '/\.git/rebase-merge/',
\     '/\.git/.*\.diff$',
\   ],
\   'hg': '/hg-editor-.\{6}\.txt$',
\   'bzr': '/bzr_log\..\{6}$',
\   'yaourt': '^/tmp/yaourt-tmp-[^/]\+/',
\ })
call s:def('g:singleton#group', $USER . $USERNAME)
call s:def('g:singleton#opener', 'tab drop')
call s:def('g:singleton#treat_stdin', 1)
call s:def('g:singleton#disable', 0)


function singleton#enable(...) abort
  if !has('vim_starting') || g:singleton#disable
    return
  endif

  let scenes = s:available_scenes()
  let secondaries = filter(scenes, '!v:val.is_master()')
  if empty(secondaries)
    return
  endif

  for scene in secondaries
    let s:scene = scene
    let is_successful = s:send_files_if_needed(scene)
    if is_successful
      return
    endif
  endfor
endfunction

function s:available_scenes() abort
  " sorted by priority (builtin)
  let scene_names = ['terminal', 'remote']
  let scenes = map(scene_names, 'singleton#scene#{v:val}#get()')
  return filter(scenes, 'v:val.is_available()')
endfunction

function s:send_files_if_needed(scene) abort
  " Stdin(:help --) support.
  let c = argc()
  if g:singleton#treat_stdin && c is# 0
    augroup plugin-singleton-stdin
      autocmd! StdinReadPost *
      \        call singleton#call_action('stdin', [getline(1, '$')])
    augroup END
    return 1
  endif

  " FIXME: A path that doesn't exist can not expand to fullpath.
  let files = map(argv(), 'fnamemodify(v:val, ":p")')

  " Diff mode support.
  if &diff && c <= 2
    call singleton#call_action('diff', [files])
    return 1
  endif

  " Remote edit support.
  let pattern = s:to_pattern(g:singleton#entrust_pattern)
  if c is# 1 && s:path(files[0]) =~? pattern
    call singleton#call_action('entrust', [files[0]])
    return 1
  endif

  let pattern = s:to_pattern(g:singleton#ignore_pattern)
  if pattern !=# ''
    call filter(files, 's:path(v:val) !~? pattern')
  endif
  if !empty(files)
    call singleton#call_action('file', [files])
    return 1
  endif
  return 0
endfunction

function singleton#call_action(action, args) abort
  return s:scene.call_action(a:action, a:args)
endfunction

function singleton#_getchar() abort
  try
    let c = getchar()
    return type(c) is# v:t_number ? nr2char(c) : c
  catch '^Vim:Interrupt'
    return "\<C-c>"
  endtry
endfunction


function s:to_pattern(pat) abort
  if type(a:pat) == type('')
    return a:pat
  elseif type(a:pat) == type([])
    return join(map(a:pat, 's:to_pattern(v:val)'), '\m\|')
  elseif type(a:pat) == type({})
    return s:to_pattern(values(a:pat))
  endif
  return ''
endfunction

function s:path(path) abort
  return simplify(substitute(a:path, '\\', '/', 'g'))
endfunction
