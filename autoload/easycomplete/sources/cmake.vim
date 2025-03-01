if get(g:, 'easycomplete_sources_cmake')
  finish
endif
let g:easycomplete_sources_cmake = 1

" TODO 仍未调通，应该是 cmake-languageserver 本身的 bug
" 参考：https://github.com/regen100/cmake-language-server/issues/9
function! easycomplete#sources#cmake#constructor(opt, ctx)
  call easycomplete#RegisterLspServer(a:opt, {
      \ 'name': 'cmake-language-server',
      \ 'cmd': [easycomplete#installer#GetCommand(a:opt['name'])],
      \ 'root_uri':{server_info -> "file://" . fnamemodify(expand('%'), ':p:h')},
      \ 'initialization_options': {'buildDirectory': 'build'},
      \ 'allowlist': ['cmake', 'make', 'CMakeLists.txt']
      \ })
endfunction

function! easycomplete#sources#cmake#completor(opt, ctx) abort
  return easycomplete#DoLspComplete(a:opt, a:ctx)
endfunction

function! easycomplete#sources#cmake#GotoDefinition(...)
  return easycomplete#DoLspDefinition(["cmake", "make"])
endfunction


