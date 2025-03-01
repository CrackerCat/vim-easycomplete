if exists('g:easycomplete_dart')
  finish
endif
let g:easycomplete_dart = 1

function! easycomplete#sources#dart#constructor(opt, ctx)
  call easycomplete#RegisterLspServer(a:opt, {
      \ 'name': 'dart_lsp',
      \ 'cmd': [easycomplete#installer#GetCommand(a:opt['name'])],
      \ 'root_uri':{server_info -> "file://" . fnamemodify(expand('%'), ':p:h')},
      \ 'initialization_options': v:null,
      \ 'allowlist': ['dart'],
      \ 'config': {},
      \ 'semantic_highlight': {}
      \ })
endfunction

function! easycomplete#sources#dart#completor(opt, ctx) abort
  return easycomplete#DoLspComplete(a:opt, a:ctx)
endfunction

function! easycomplete#sources#dart#GotoDefinition(...)
  return easycomplete#DoLspDefinition(["dart"])
endfunction

