set nocompatible
let &rtp = '../..,' . &rtp
filetype plugin on

let g:vimtex_cache_root = '.'
let g:vimtex_cache_persistent = 0

silent edit test-abort.tex

if empty($INMAKE) | finish | endif
if !has('unix') | call vimtex#test#finished() | endif

" Send a real interrupt while the parser is processing an include.
function! s:interrupt() abort
  let l:cmd = ['sh', '-c', 'sleep 0.01; kill -INT ' . getpid()]
  let l:job = has('nvim') ? jobstart(l:cmd) : job_start(l:cmd)
  sleep 1
  call assert_report('Did not receive the interrupt')
endfunction

let s:cwd = getcwd()
for s:api in ['omnifunc', 'complete']
  call vimtex#cache#close('parser_tex')

  " Bypass the source-file timestamp scan to interrupt candidate gathering.
  function! b:vimtex.getftime() abort
    return getftime(self.tex)
  endfunction

  " Redefine only after autoloading, so Vim permits replacing this function.
  function! vimtex#parser#tex#input_parser(line, current_file, root) abort
    call s:interrupt()
  endfunction

  if s:api ==# 'omnifunc'
    call setline(1, '\test')
    call cursor(1, 5)
    call assert_equal(1, vimtex#complete#omnifunc(1, ''))
    let s:pos = getpos('.')
    call assert_equal([], vimtex#complete#omnifunc(0, 'test'))
  else
    let s:pos = getpos('.')
    call assert_equal([], vimtex#complete#complete('cmd', 'test', '\'))
  endif

  call assert_equal(s:cwd, getcwd())
  call assert_equal(s:pos, getpos('.'))
  runtime autoload/vimtex/parser/tex.vim

  " A retry must reparse the interrupted file, without clearing its cache.
  let s:words = map(vimtex#complete#complete('cmd', 'test', '\'),
        \ 'v:val.word')
  call assert_equal(['testbefore', 'testafter'], s:words)

  " Force another document scan for the next entry point.
  let s:cache = vimtex#cache#open('pkgcomplete')
  let s:current = s:cache.get(sha256(b:vimtex.tex))
  let s:current.ftime = -1
endfor

" Bibliography discovery changes directory before scanning included files.
call vimtex#bib#files()
function! vimtex#bib#files() abort
  call s:interrupt()
endfunction
cd ..
let s:cwd = getcwd()
call assert_equal([], vimtex#complete#complete('bib', '', '\cite{'))
call assert_equal(s:cwd, getcwd())
call vimtex#paths#pushd(b:vimtex.root)
call vimtex#paths#popd()
call assert_equal(s:cwd, getcwd())
execute 'cd' fnameescape(b:vimtex.root)

call vimtex#test#finished()
