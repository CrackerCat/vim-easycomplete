if get(g:, 'easycomplete_sources_java')
  finish
endif
let g:easycomplete_sources_java = 1

function! easycomplete#sources#java#constructor(opt, ctx)
  " 注册 lsp
  call easycomplete#RegisterLspServer(a:opt, {
      \ 'name': 'vim-lsp-java.eclipse-jdtls',
      \ 'cmd': {server_info->[easycomplete#installer#GetCommand(a:opt['name'])]},
      \ 'allowlist': ['java'],
      \ })
endfunction

function! easycomplete#sources#java#completor(opt, ctx) abort
  return easycomplete#DoLspComplete(a:opt, a:ctx)
endfunction

function! easycomplete#sources#java#GotoDefinition(...)
  return easycomplete#DoLspDefinition(["java"])
endfunction

function! s:log(...)
  return call('easycomplete#util#log', a:000)
endfunction
