" File:         easycomplete.vim
" Author:       @jayli <https://github.com/jayli/>
" Description:  A minimalism style complete plugin for vim/nvim
" More Info:    <https://github.com/jayli/vim-easycomplete>

if get(g:, 'easycomplete_script_loaded')
  finish
endif
let g:easycomplete_script_loaded = 1

function! easycomplete#LogStart()
  " call s:console()
endfunction

" 全局 Complete 注册插件，其中插件和 LSP Server 是包含关系
"   g:easycomplete_source['vim'].lsp 指向 lsp config
let g:easycomplete_source  = {}
" 匹配过程中的缓存，主要处理 <BS> 和 <CR> 后显示 Complete 历史
let g:easycomplete_menucache = {}
" 匹配过程中的全量匹配数据，CompleteDone 后置空
let g:easycomplete_menuitems = []
" 显示 complete menu 所需的临时 items，根据 maxlength 截断
let g:easycomplete_complete_ctx = {}
" 隐式匹配菜单所需的临时 items，缓存全量匹配菜单数据，用以给
" SecondComplete 提速用
let g:easycomplete_stunt_menuitems= []
" 保存 v:event.complete_item, 判断是否 pum 处于选中状态
let g:easycomplete_completed_item = {}
" 全局时间的标记，性能统计时用
let g:easycomplete_start = reltime()
" HACK: 当从 pum 最后一项继续 tab 到第一项时，此时也应当避免发生 completedone
" 需要选择匹配项过程中的过程变量 ctx 暂存下来
let g:easycomplete_firstcomplete_ctx = {}
" 和 YCM 一样，用做 FirstComplete 标志位
let g:easycomplete_first_complete_hit = 0
" 菜单显示最大 item 数量，默认和 coc 保持一致
" viml 的跟指性能不佳，适当降低下 maxlength 的阈值到 35
let g:easycomplete_maxlength = (&filetype == 'vim' && !has('nvim') ? 35 : 50)
" Global CompleteChanged Event：异步回调显示 popup 时借用
let g:easycomplete_completechanged_event = {}
let g:easycomplete_diagnostics_render_delay = 200
" 用来判断是否是 c-v 粘贴
let g:easycomplete_insert_char = ''
" First complete 过程中的任务队列，所有队列任务都完成后才显示匹配菜单
" [
"   {
"     "ctx": {},
"     "name": "ts",
"     "condition": 0
"     "done" : 0
"   }
" ]
let g:easycomplete_complete_taskqueue = []
let g:easycomplete_popup_width = 50
" 当前敲入的字符所属的 ctx，主要用来判断光标前进还是后退
let b:typing_ctx = {}
let b:old_changedtick = 0
let g:easycomplete_backing = 0
" <BS> 或者 <CR>, 以及其他非 ASCII 字符时的标志位
" zizz 标志位
let g:easycomplete_backing_or_cr = 0
" 用作 FirstComplete TaskQueue 回调的定时器
let s:first_render_timer = 0
" FirstCompleteRendering 中 LSP 的超时时间
let g:easycomplete_first_render_delay = 1500

" EasyComplete 入口函数
function! easycomplete#Enable()
  if !easycomplete#util#EnvReady() | return | endif
  call easycomplete#LogStart()
  " 插件要求在每个 BufferEnter 时调用
  if exists("b:easycomplete_loaded_done")
    return
  endif
  let b:easycomplete_loaded_done= 1

  doautocmd <nomodeline> User easycomplete_default_plugin
  doautocmd <nomodeline> User easycomplete_custom_plugin
  call s:InitLocalVars()
  " 要注意绑定顺序：
  "  - 必须要确保typing command先绑定
  "  - 然后绑定插件里的typing command
  call s:BindingTypingCommandOnce()
  call easycomplete#log#init()
  call s:ConstructorCalling()
  call s:SetupCompleteCache()
  call easycomplete#ui#SetScheme()
  " lsp 服务初始化必须要放在按键绑定之后
  call easycomplete#lsp#enable()
  if easycomplete#ok('g:easycomplete_diagnostics_enable')
    call easycomplete#sign#init()
    call s:AsyncRun(function('easycomplete#lsp#diagnostics_enable'),[
          \ {'callback':function('easycomplete#action#diagnostics#HandleCallback')}
          \ ], 150)
  endif
  call timer_start(300, { -> easycomplete#AutoLoadDict() })
endfunction

function! s:InitLocalVars()
  if !exists("g:easycomplete_tab_trigger")
    let g:easycomplete_tab_trigger = "<Tab>"
  endif
  if !exists("g:easycomplete_shift_tab_trigger")
    let g:easycomplete_shift_tab_trigger = "<S-Tab>"
  endif
  let b:typing_ctx = easycomplete#context()
  setlocal completeopt-=menu
  setlocal completeopt+=noinsert
  setlocal completeopt+=menuone
  setlocal completeopt+=noselect
  setlocal completeopt-=popup
  setlocal completeopt-=preview
  setlocal completeopt-=longest
  setlocal cpoptions+=B
endfunction

function! easycomplete#GetBindingKeys()
  " 通用触发跟指匹配的字符绑定，所有文档类型生效
  " 另外每个插件可自定义触发按键，在插件的 semantic_triggers 中定义
  let l:key_liststr = 'abcdefghijklmnopqrstuvwxyz'.
                    \ 'ABCDEFGHIJKLMNOPQRSTUVWXYZ#/._'
  return l:key_liststr
endfunction

function! s:BindingTypingCommandOnce()
  if get(g:, 'easycomplete_typing_binding_done')
    return
  endif
  let g:easycomplete_typing_binding_done = 1
  if s:SnipSupports() && g:UltiSnipsExpandTrigger ==? g:easycomplete_tab_trigger
    " Ultisnips 的默认 tab 键映射和 EasyComplete 冲突，需要先unmap掉
    exec "iunmap " . g:easycomplete_tab_trigger
  endif
  exec "inoremap <silent><expr> " . g:easycomplete_tab_trigger . "  easycomplete#CleverTab()"
  exec "inoremap <silent><expr> " . g:easycomplete_shift_tab_trigger . "  easycomplete#CleverShiftTab()"
  try
    nnoremap <silent><unique> <C-j> :EasyCompleteNextDiagnostic<CR>
    nnoremap <silent><unique> <C-k> :EasyCompletePreviousDiagnostic<CR>
  catch /^Vim\%((\a\+)\)\=:E227/
    call easycomplete#util#log(
          \ 'You should set Diagnostic jumping map-key manully. `:h easycomplete` for help'
          \ )
  endtry

  " TODO 不生效
  " inoremap <Tab> <Plug>EasycompleteTabTrigger
  " 重定向 Tag 的跳转按键绑定，和默认<c-]>功能一致
  nnoremap <silent> <c-]> :EasyCompleteGotoDefinition<CR>
endfunction

" 检查当前注册的插件中所依赖的 command 是否已经安装
function! easycomplete#checking()
  call s:flush()
  let amsg = ["Checking lsp cmd tools dependencies:"]
  call add(amsg, "")
  for item in keys(g:easycomplete_source)
    let l:name = item
    if !has_key(g:easycomplete_source[item], 'command')
      continue
    endif
    let l:command = get(g:easycomplete_source[item], 'command')
    let l:flag_txt = easycomplete#installer#executable(l:command) ? "*ready*" : "|missing|"
    let l:flag_ico = easycomplete#installer#executable(l:command) ? "√" : "×"
    let l:msg = "[".l:flag_ico."]" . " " . l:name . ": `" . l:command . "` " . l:flag_txt
    call add(amsg, l:msg)
  endfor
  call add(amsg, "")
  call add(amsg, "Done")
  let current_winid = bufwinid(bufnr(""))
  vertical botright new
  setlocal previewwindow filetype=help buftype=nofile nobuflisted modifiable
  let message_winid = bufwinid(bufnr(""))
  let ix = 0
  for line in amsg
    let ix = ix + 1
    call setbufline(bufnr(""), ix, line)
  endfor
endfunction

function! easycomplete#GetAllPlugins()
  return copy(g:easycomplete_source)
endfunction

function! easycomplete#GetCurrentLspContext()
  let l:ctx = easycomplete#context()
  let l:ctx_name = ''
  if empty(g:easycomplete_source)
    return {}
  endif
  for item in keys(g:easycomplete_source)
    if s:CompleteSourceReady(item)
      if has_key(get(g:easycomplete_source, item), "gotodefinition")
        let l:ctx_name = item
        break
      endif
    endif
  endfor
  return get(g:easycomplete_source, item, {})
endfunction

" Second Complete Entry
function! s:CompleteTypingMatch(...)
  if (empty(v:completed_item) && s:zizzing()) && !(s:VimColonTyping() || s:VimDotTyping())
    return
  endif
  let l:char = easycomplete#context()["char"]
  " 非 ASCII 码时终止
  if char2nr(l:char) < 33
    call s:CloseCompletionMenu()
    call s:flush()
    return
  endif
  if char2nr(l:char) > 126
    call timer_start(4, { -> s:CloseCompletionMenu() })
    call s:flush()
    return
  endif
  if !get(g:, 'easycomplete_first_complete_hit')
    return
  endif

  let word = exists('a:1') ? a:1 : s:GetTypingWord()
  let local_menuitems = []
  if !empty(g:easycomplete_stunt_menuitems)
    let local_menuitems = g:easycomplete_stunt_menuitems
  else
    let local_menuitems = g:easycomplete_menuitems
  endif
  let filtered_menu = easycomplete#util#CompleteMenuFilter(local_menuitems, word, 250)
  if len(filtered_menu) == 0
    call s:CloseCompletionMenu()
    let g:easycomplete_stunt_menuitems = []
    return
  endif

  " 如果在 VIM 中输入了':'和'.'，一旦没有匹配项，就直接清空
  " g:easycomplete_menuitems，匹配状态复位
  " 注意：这里其实区分了 跟随匹配 和 Tab 匹配两个不同的动作
  " - 跟随匹配内容尽可能少，能匹配不出东西就保持空，尽可能少的干扰
  " - Tab 匹配内容尽可能多，能多匹配就多匹配，交给用户去选择
  if (len(filtered_menu) == 0) && (s:VimDotTyping() || s:VimColonTyping())
    call s:CloseCompletionMenu()
    call s:flush()
    return
  endif
  call s:SecondComplete(col('.') - strlen(word), filtered_menu, g:easycomplete_menuitems, word)
endfunction

function! s:SecondComplete(start_pos, menuitems, easycomplete_menuitems, word)
  let tmp_menuitems = copy(a:easycomplete_menuitems)
  let g:easycomplete_stunt_menuitems = copy(a:menuitems)
  let result = a:menuitems[0 : g:easycomplete_maxlength]
  if len(result) <= 5
    let result = easycomplete#util#uniq(result)
  endif
  " ===================================
  if g:env_is_iterm
    call s:StopAsyncRun()
    if len(g:easycomplete_stunt_menuitems) < 40
      call s:AsyncRun(function('s:complete'), [a:start_pos, result], 0)
    else
      call s:StopAsyncRun()
      call s:AsyncRun(function('easycomplete#_complete'), [a:start_pos, result], 0)
    endif
  else
    call s:StopAsyncRun()
    call s:AsyncRun(function('s:complete'), [a:start_pos, result], 0)
  endif
  " ===================================
  call s:AddCompleteCache(a:word, deepcopy(g:easycomplete_stunt_menuitems))
  " complete() 会触发 completedone 事件，会执行 s:flush()
  " 所以这里要确保 g:easycomplete_menuitems 不会被修改
  let g:easycomplete_menuitems = tmp_menuitems
endfunction

function! easycomplete#CompleteDone()
  call easycomplete#popup#CompleteDone()
  if !s:SameCtx(easycomplete#context(), g:easycomplete_firstcomplete_ctx) && !s:zizzing()
    return
  endif
  " bugfix for #88
  if pumvisible() || (empty(v:completed_item) && g:easycomplete_first_complete_hit != 1)
    call s:zizz()
    return
  endif
  call s:flush()
endfunction

function! easycomplete#InsertLeave()
  if easycomplete#ok('g:easycomplete_diagnostics_enable')
    call easycomplete#lint()
    call easycomplete#sign#LintCurrentLine()
  endif
  if s:zizzing()
    return
  endif
  call easycomplete#popup#InsertLeave()
  call s:flush()
endfunction

function! easycomplete#flush()
  call s:flush()
endfunction

" 判断 pum 是否是选中状态
function! easycomplete#CompleteCursored()
  if !pumvisible()
    return v:false
  endif
  return complete_info()['selected'] == -1 ? v:false : v:true
endfunction

function! easycomplete#SetCompletedItem(item)
  let g:easycomplete_completed_item = a:item
endfunction

function! easycomplete#GetCompletedItem()
  return g:easycomplete_completed_item
endfunction

function! easycomplete#IsBacking()
  return g:easycomplete_backing
endfunction

function! s:BackChecking()
  let curr_ctx = easycomplete#context()
  if !exists('b:typing_ctx')
    let b:typing_ctx = easycomplete#context()
  endif
  let old_ctx = deepcopy(b:typing_ctx)
  let b:typing_ctx = curr_ctx
  if empty(curr_ctx) || empty(old_ctx) | return v:false | endif
  if get(curr_ctx, 'lnum') == get(old_ctx,'lnum')
        \ && strlen(get(old_ctx,'typed',"")) >= 2
    if curr_ctx['typed'] ==# old_ctx['typed'][:-2]
      " 单行后退非到达首字母的后退
      return v:true
    endif
    if curr_ctx['typed'] ==# old_ctx['typed']
      " 单行在 Normal 模式下按下 s 键
      return v:true
    endif
  elseif get(curr_ctx,'lnum') == get(old_ctx,'lnum')
        \ && strlen(old_ctx['typed']) == 1 && strlen(curr_ctx['typed']) == 0
    " 单行后退到达首字母的后退
    return v:true
  elseif old_ctx['lnum'] == curr_ctx['lnum'] + 1 && old_ctx['col'] == 1
    " 隔行后退
    return v:true
  else
    return v:false
  endif
endfunction

function! easycomplete#Up()
  if pumvisible()
    call s:zizz()
  endif
  call easycomplete#popup#close("float")
  return "\<Up>"
endfunction

function! easycomplete#Down()
  if pumvisible()
    call s:zizz()
  endif
  call easycomplete#popup#close("float")
  return "\<Down>"
endfunction

" 参考 asynccomplete 并做了扩充
function! easycomplete#context() abort
  let l:ret = {
        \ 'bufnr':bufnr('%'),
        \ 'curpos':getcurpos(),
        \ 'changedtick':b:changedtick
        \ }
  let l:ret['lnum'] = l:ret['curpos'][1] " 行号
  let l:ret['col'] = l:ret['curpos'][2] " 列号
  let l:ret['filetype'] = &filetype " filetype
  let l:ret['filepath'] = expand('%:p') " filepath
  let line = getline(l:ret['lnum']) " 当前行内容
  let l:ret['typed'] = strpart(line, 0, l:ret['col']-1) " 光标前敲入的内容
  let l:ret['char'] = strpart(line, l:ret['col']-2, 1) " 当前单个字符
  let l:ret['typing'] = s:GetTypingWord() " 当前敲入的单词
  let l:ret['startcol'] = l:ret['col'] - strlen(l:ret['typing']) " 单词起始位置
  return l:ret
endfunction

function! easycomplete#CheckContextSequence(ctx)
  return s:SameCtx(a:ctx, easycomplete#context())
endfunction

function! s:OrigionalPosition()
  return easycomplete#CheckContextSequence(g:easycomplete_firstcomplete_ctx)
endfunction

" 外部插件回调的 API
function! easycomplete#complete(name, ctx, startcol, items, ...) abort
  if s:NotInsertMode()
    call s:flush()
    return
  endif
  let l:ctx = easycomplete#context()
  if !s:SameCtx(a:ctx, l:ctx)
    return
  endif
  call s:SetCompleteTaskQueue(a:name, l:ctx, 1, 1)
  call s:CompleteAdd(a:items, a:name)
endfunction

function! s:CallConstructorByName(name, ctx)
  let l:opt = get(g:easycomplete_source, a:name)
  let b:constructor = get(l:opt, "constructor")
  if empty(b:constructor)
    return v:null
  endif
  if type(b:constructor) == 2 " type is function
    call b:constructor(l:opt, a:ctx)
  endif
  if type(b:constructor) == type("string") " type is string
    call call(b:constructor, [l:opt, a:ctx])
  endif
endfunction

function! s:CallCompeltorByName(name, ctx)
  let l:opt = get(g:easycomplete_source, a:name)
  if empty(l:opt) || empty(get(l:opt, "completor"))
    return v:true
  endif
  let b:completor = get(l:opt, "completor")
  if type(b:completor) == 2 " type is function
    return b:completor(l:opt, a:ctx)
  endif
  if type(b:completor) == type("string") " type is string
    return call(b:completor, [l:opt, a:ctx])
  endif
endfunction

function! easycomplete#FireCondition()
  return s:NormalTrigger() || s:SemanticTrigger()
endfunction

" 是否符合某个插件自定义的条件 trigger，包含:true, 不包含:false
function! s:SemanticTrigger()
  let flag = v:false
  for name in keys(g:easycomplete_source)
    if s:CompleteSourceReady(name) && s:SemanticTriggerForPluginName(name)
      let flag = v:true
      break
    endif
  endfor
  return flag
endfunction

function! s:SemanticTriggerForPluginName(name)
  let ctx = easycomplete#context()
  let trigger_keys = get(g:easycomplete_source[a:name], 'semantic_triggers', [])
  if empty(trigger_keys) | return v:false | endif
  for item_rgx in trigger_keys
    if ctx['typed'] =~ item_rgx
      return v:true
    endif
  endfor
  return v:false
endfunction

" 是否匹配通用字符 trigger
function! s:NormalTrigger()
  let l:char = easycomplete#context()["char"]
  if s:zizzing() && index([":",".","_","/",">"], l:char) < 0
    return v:false
  endif
  " if s:PythonColonTyping()
  "   return v:false
  " endif
  let binding_keys = easycomplete#GetBindingKeys()
  if index(easycomplete#util#str2list(binding_keys), char2nr(l:char)) >= 0
    return v:true
  endif
  return v:false
endfunction

" python 的冒号
function! s:PythonColonTyping()
  if &filetype == "python" &&
        \ easycomplete#context()['typed'] =~ "\\(\\w\\|)\\):$"
    return v:true
  else
    return v:false
  endif
endfunction

" C++ 的双冒号
function! s:CppColonTyping()
  if &filetype == "cpp" &&
        \ easycomplete#context()['typed'] =~ "\\w::$"
    return v:true
  else
    return v:false
  endif
endfunction

" C++ 的箭头
function! s:CppArrowTyping()
  if &filetype == "cpp" &&
        \ easycomplete#context()['typed'] =~ "->$"
    return v:true
  else
    return v:false
  endif
endfunction

" vim 的冒号
function! s:VimColonTyping()
  if &filetype == "vim" &&
        \ (
        \   easycomplete#context()['typed'] =~ "\\W\\(w\\|t\\|a\\|b\\|v\\|s\\|g\\):$"
        \   ||
        \   easycomplete#context()['typed'] =~ "^\\(w\\|t\\|a\\|b\\|v\\|s\\|g\\):$"
        \ )
    return v:true
  else
    return v:false
  endif
endfunction

" vim 的点号
function! s:VimDotTyping()
  if &filetype == "vim" && easycomplete#context()['typed'] =~ '\(\w\+\.\)\{-1,}$'
    return v:true
  else
    return v:false
  endif
endfunction

function! easycomplete#InsertCharPre()
  let g:easycomplete_insert_char = v:char
endfunction

function! s:ResetInsertChar()
  let g:easycomplete_insert_char = ""
endfunction

function! s:BackingCompleteHandler()
  let g:easycomplete_backing = 1
  let g:easycomplete_stunt_menuitems = []
  call s:zizz()
  let ctx = easycomplete#context()
  if empty(ctx["typing"]) || empty(ctx['char'])
        \ || !s:SameBeginning(g:easycomplete_firstcomplete_ctx, ctx)
    silent! noa call s:CloseCompletionMenu()
    call s:flush()
  else
    let g:easycomplete_stunt_menuitems = []
    if !empty(g:easycomplete_menuitems)
      let g:easycomplete_stunt_menuitems = s:GetCompleteCache(s:GetTypingWordByGtx())['menu_items']
      let start_pos = col('.') - strlen(s:GetTypingWordByGtx())
      let result = g:easycomplete_stunt_menuitems[0 : g:easycomplete_maxlength]
      call s:complete(start_pos, result)
    endif
  endif
endfunction

function! easycomplete#BackSpace()
  return "\<BS>"
endfunction

" 正常输入和退格监听函数
" for firstcompele typing and back typing
function! easycomplete#typing()
  let g:easycomplete_start = reltime()
  if s:BackChecking()
    let g:easycomplete_backing = 1
    call s:BackingCompleteHandler()
    return ""
  else
    let g:easycomplete_backing = 0
  endif

  " 判断是否是 C-V 粘贴
  call s:AsyncRun(function('s:ResetInsertChar'), [], 30)
  if empty(g:easycomplete_insert_char)
    return ""
  endif

  if !easycomplete#FireCondition()
    return ""
  endif

  " hack for vim ':' typing
  if &filetype == 'vim' && easycomplete#context()['char'] == ":"
    if !s:VimColonTyping()
      return ""
    endif
  endif

  " vim lsp 返回结果中包含多层的对象，比如 "a.b.c"，这样在输入"." 时就需要匹配
  " 返回结果中的"."，":" 也是同理，这里只对 viml 做特殊处理
  if s:VimColonTyping()
    " continue
  elseif s:VimDotTyping()
    " continue
  elseif s:zizzing()
    return ""
  endif

  if pumvisible()
    return ""
  endif

  let b:typing_ctx = easycomplete#context()

  call s:StopAsyncRun()
  call s:DoComplete(v:false)
  return ""
endfunction

" immediately: 是否立即执行 complete()
" 在 '/' 或者 '.' 触发目录匹配时立即执行
function! s:DoComplete(immediately)
  let l:ctx = easycomplete#context()
  " 过滤不连续的 '.'
  if strlen(l:ctx['typed']) >= 2 && l:ctx['char'] ==# '.'
        \ && l:ctx['typed'][l:ctx['col'] - 3] !~ '^[a-zA-Z0-9]$'
    call s:CloseCompletionMenu()
    return v:null
  endif

  " sh #!<tab> hack, bugfix #12
  if &filetype == "sh" && easycomplete#context()['typed'] == "#!"
    call s:AsyncRun(function('s:CompleteHandler'), [], 0)
    return v:null
  endif

  if complete_check()
    call s:flush()
    return v:null
  endif

  " One ':' or '.', Do nothing
  if strlen(l:ctx['typed']) == 1 && (l:ctx['char'] ==# '.' || l:ctx['char'] ==# ':')
    call s:CloseCompletionMenu()
    return v:null
  endif

  " 连续两个 '.' 重新初始化 complete
  if l:ctx['char'] == '.' &&
        \ (len(l:ctx['typed']) >= 2 && easycomplete#util#str2list(l:ctx['typed'])[-2] == char2nr('.'))
    call s:CompleteInit()
    call s:ResetCompleteCache()
  endif

  " 首次按键给一个延迟，体验更好
  if index([':','.','/'], l:ctx['char']) >= 0 || a:immediately == v:true
    let word_first_type_delay = 0
  else
    let word_first_type_delay = 5
  endif

  " typing 中的 SecondComplete 特殊字符处理
  " 特殊字符'->',':','.','::'等 在个语言中的匹配，一般要配合 lsp 一起使用，即
  " lsp给出的结果中就包含了 "a.b.c" 的提示，这时直接执行 SecondComplete 动作
  if !empty(g:easycomplete_menuitems)
    " hack for vim ':' colon typing
    if s:VimColonTyping()
      let l:vim_word = matchstr(l:ctx['typed'], '\w:$')
      call s:CompleteTypingMatch(l:vim_word)
      return v:null
    endif
  endif

  " 检查模糊匹配 fuzzy match 条件
  if !empty(g:easycomplete_menuitems)
        \ && !s:SameCtx(easycomplete#context(), g:easycomplete_firstcomplete_ctx)
        \ && s:SameBeginning(g:easycomplete_firstcomplete_ctx, easycomplete#context())
    call s:CompleteTypingMatch()
    return v:null
  endif

  " 如果不是 insert 模式
  if g:env_is_nvim && mode() != 'i'
    return v:null
  endif

  " 执行 DoComplete
  call s:StopAsyncRun()
  call s:AsyncRun(function('s:CompleteHandler'), [], word_first_type_delay)
  return v:null
endfunction

" 插件注册样例:
" call easycomplete#RegisterSource({
"     \ 'name': 'buffer',
"     \ 'allowlist': ['*'],
"     \ 'blocklist': ['go'],
"     \ 'completor': function('easycomplete#sources#buffer#completor'),
"     \ 'config': {
"     \    'max_buffer_size': 5000000,
"     \  },
"     \ })
function! easycomplete#RegisterSource(opt)
  if !has_key(a:opt, "name")
    return
  endif
  if !exists("g:easycomplete_source")
    let g:easycomplete_source = {}
  endif
  let g:easycomplete_source[a:opt["name"]] = a:opt
endfunction

function! easycomplete#RegisterLspServer(opt, config)
  let cmd = get(a:opt, 'command', '')
  if empty(cmd)
    let l:not_defined_msg = 'Plugin command name is not defined.'
    " Bugfix for #83
    if g:env_is_nvim
      call s:AsyncRun(function("easycomplete#util#info"), [l:not_defined_msg], 1)
    else
      call easycomplete#util#info(l:not_defined_msg)
    endif
    return
  endif
  if !easycomplete#installer#executable(cmd)
    let l:lsp_installing_msg = "'". cmd ."' is not avilable. Do ':InstallLspServer'"
    if g:easycomplete_lsp_checking
      if g:env_is_nvim
          call s:AsyncRun(function("easycomplete#util#info"), [l:lsp_installing_msg], 1)
      else
        call easycomplete#util#info(l:lsp_installing_msg)
      endif
    endif
    return
  endif
  let g:easycomplete_source[a:opt["name"]].lsp = copy(a:config)
  call easycomplete#lsp#register_server(a:config)
endfunction

function! easycomplete#GetPluginNameByLspName(lsp_name)
  let plugin_name = ""
  for item in keys(g:easycomplete_source)
    let lsp = get(g:easycomplete_source[item], 'lsp', {})
    if !empty(lsp) && lsp['name'] ==# a:lsp_name
      let plugin_name = item
      break
    endif
  endfor
  return plugin_name
endfunction

function! easycomplete#GetFirstRenderTimer()
  return s:first_render_timer
endfunction

function! easycomplete#ResetFirstRenderTimer()
  let s:first_render_timer = 0
endfunction

" 从注册的插件中依次调用每个 completor 函数，此函数只在 FirstComplete 时调用
" 每个 completor 中给出匹配结果后回调给 CompleteAdd
function! s:CompletorCallingAtFirstComplete(...)
  let l:ctx = easycomplete#context()
  call s:ResetCompleteTaskQueue()
  if s:first_render_timer > 0
    call timer_stop(s:first_render_timer)
  endif
  let s:first_render_timer = timer_start(g:easycomplete_first_render_delay,
        \ { -> easycomplete#util#call(function("s:FirstCompleteRendering"),
        \          [
        \            s:GetCompleteCache(l:ctx['typing'])['start_pos'],
        \            s:GetCompleteCache(l:ctx['typing'])['menu_items']
        \          ])
        \ })
  try

  " TODO 原本在设计 CompletorCalling 机制时，每个CallCompeltorByName返回true时继
  " 续执行，返回false中断执行，目的是为了实现那些排他性的CompleteCalling，比如
  " directory. 但在 runtime 中不能很好的执行，因为每个 complete_plugin 的
  " completor 的调用顺序不确定，如果让所有 completor 全都异步，是可以实现排他性
  " complete的，但即便每个调用都是异步，对于 lsp request 已经发出的情况，由于不
  " 能abort掉 lsp 进程，因此还是会有返回值冲刷进 g:easycomplete_menuitems，进而
  " 污染匹配结果。
  "
  " 这里用了一个 Hack 来缓解这个问题，即当前只有 directory 一个插件的情况下，把
  " 唯一一个 return false 的 directory 放在最前面做循环，勉强解决掉这个问题
  "
  " 这里设计上需要重新考虑下，是否是只能有一个排他completor，还是存在多个共存的
  " 情况，还不清楚，先这样hack掉
    let source_names = ['directory']
    for name in keys(g:easycomplete_source)
      if name !=# 'directory'
        call add(source_names, name)
      endif
    endfor

    let l:count = 0
    while l:count < len(source_names)
      let item = source_names[l:count]
      let l:count += 1
      if s:CompleteSourceReady(item) && (s:NormalTrigger() || s:SemanticTriggerForPluginName(item))
        let l:cprst = s:CallCompeltorByName(item, l:ctx)
        if l:cprst == v:true " true: 继续
          continue
        else
          call s:flush()
          call s:LetCompleteTaskQueueAllDone()
          break " false: break, 只在 directory 文件目录匹配时使用
        endif
      endif
    endwhile
  catch
    echom v:exception
    call s:flush()
  endtry
endfunction

function! s:ConstructorCalling(...)
  let l:ctx = easycomplete#context()
  for item in keys(g:easycomplete_source)
    if s:CompleteSourceReady(item)
      call s:CallConstructorByName(item, l:ctx)
    endif
  endfor
endfunction

function! easycomplete#CompleteSourceReady(name)
  return s:CompleteSourceReady(a:name)
endfunction

function! s:CompleteSourceReady(name)
  if has_key(g:easycomplete_source, a:name)
    let completor_source = get(g:easycomplete_source, a:name)
    if has_key(completor_source, 'whitelist')
      let whitelist = get(completor_source, 'whitelist')
      if index(whitelist, &filetype) >= 0 || index(whitelist, "*") >= 0
        return v:true
      else
        return v:false
      endif
    else
      return v:true
    endif
  else
    return v:false
  endif
endfunction

" 这个函数只能在 SecondComplete 过程中使用
" 用来根据 g:easycomplete_firstcomplete_ctx 和 ctx 做 diff 算出 typing word
"   For example:
"     步骤1. 输入 app 按 Tab 执行 FristComplete
"         app<Tab>
"         append
"         appendTo
"         apple
"         appleId
"         applyBufline
"
"     步骤2. 继续输入 end 执行 SecondComplete
"         append<Typing>
"         append
"         appendTo
"       这时 SecondComplete 中根据`end`过滤 FristComplete 返回的全量匹配词表
"       GetTypingWordByGtx() 即返回 `end` 被带入到 CompleteTypingMatch() 中
"
" Gtx 即 g:easycomplete_firstcomplete_ctx
function! s:GetTypingWordByGtx()
  if empty(g:easycomplete_firstcomplete_ctx)
    return ""
  endif
  let l:ctx = easycomplete#context()
  let l:gtx = g:easycomplete_firstcomplete_ctx
  let offset = l:gtx['startcol'] - l:ctx['startcol']
  return l:ctx['typed'][strlen(l:gtx['typed']) - strlen(l:gtx['typing']) - offset:]
endfunction

" 只针对 FirstComplete 完成后的结果进行 Match 匹配动作，不再重新请求 LSP
function! s:CompleteMatchAction()
  try
    call s:StopZizz()
    let l:vim_word = s:GetTypingWordByGtx()
    call s:CompleteTypingMatch(l:vim_word)
    let b:typing_ctx = easycomplete#context()
  catch
    echom v:exception
  endtry
endfunction

function! easycomplete#CompleteChanged()
  let item = deepcopy(v:event.completed_item)
  call easycomplete#SetCompletedItem(item)
  if empty(item)
    call s:CloseCompleteInfo()
    return
  endif
  let b:typing_ctx = easycomplete#context()
  call easycomplete#ShowCompleteInfoByItem(item)

  " Hack 所有异步获取 document 时，需要暂存 event
  let g:easycomplete_completechanged_event = deepcopy(v:event)
endfunction

function! s:CloseCompleteInfo()
  if g:env_is_nvim
    call easycomplete#popup#MenuPopupChanged([])
  else
    call easycomplete#popup#close("popup")
  endif
endfunction

function! easycomplete#ShowCompleteInfoByItem(item)
  let info = easycomplete#util#GetInfoByCompleteItem(copy(a:item), g:easycomplete_menuitems)
  let async = empty(info) ? v:true : v:false
  if easycomplete#util#ItemIsFromLS(a:item) && (async || index(["rb"], easycomplete#util#GetLspPluginName()) >= 0)
    call s:StopAsyncRun()
    call s:AsyncRun(function('easycomplete#action#documentation#LspRequest'), [a:item], 80)
  else
    if type(info) == type("")
      let info = [info]
    endif
    " hack from documentation.vim
    if exists('b:easycomplete_documentation_popup') && b:easycomplete_documentation_popup > 0
      call timer_stop(b:easycomplete_documentation_popup)
    endif
    call s:ShowCompleteInfo(info)
  endif
endfunction

function easycomplete#ShowCompleteInfo(info)
  call s:ShowCompleteInfo(a:info)
endfunction

function! s:ShowCompleteInfo(info)
  call easycomplete#HandleTagbarUpdateAction()
  call easycomplete#popup#MenuPopupChanged(a:info)
endfunction

function easycomplete#HandleTagbarUpdateAction()
  if easycomplete#util#TagBarExists()
    try
      call tagbar#StopAutoUpdate()
    catch /^Vim\%((\a\+)\)\=:E216/
      " Do Nothing
    endtry
  endif
endfunction

function s:ModifyInfoByMaxwidth(...)
  return call('easycomplete#util#ModifyInfoByMaxwidth', a:000)
endfunction

function! easycomplete#SetMenuInfo(name, info, menu_flag)
  for item in g:easycomplete_menuitems
    let t_name = easycomplete#util#GetItemWord(item)
    if t_name ==# a:name && get(item, "menu") ==# a:menu_flag
      let item.info = a:info
      break
    endif
  endfor
endfunction

function! easycomplete#CleverTab()
  if pumvisible()
    call s:zizz()
    return "\<C-N>"
  elseif &filetype == "sh" && easycomplete#context()['typed'] == "#!"
    " sh #!<tab> hack, bugfix #12
    call s:ExpandSnipManually("#!")
    return ""
  elseif s:SnipSupports() && UltiSnips#CanJumpForwards()
    " 安装了 Ultisnips 后，用 Tab 来前跳
    " call UltiSnips#JumpForwards()
    call s:zizz()
    call eval('feedkeys("\'. g:UltiSnipsJumpForwardTrigger .'")')
    return ""
  elseif  getline('.')[0 : col('.')-1]  =~ '^\s*$' ||
        \ getline('.')[col('.')-2 : col('.')-1] =~ '^\s$' ||
        \ len(s:StringTrim(getline('.'))) == 0
    " 空行检查:
    "   whole empty line
    "   a space char before
    "   empty line
    call s:zizz()
    return "\<Tab>"
  elseif s:CppArrowTyping()
    call s:DoTabCompleteAction()
    return ""
  elseif match(strpart(getline('.'), 0 ,col('.') - 1)[0:col('.')-1],
        \ "\\(\\w\\|\\/\\|\\.\\|\\:\\)$") < 0
    " 输入非字母表字符，同时也不是 '/' 或者 ':'
    call s:zizz()
    return "\<Tab>"
  else
    call s:DoTabCompleteAction()
    return ""
  endif
endfunction

function! s:DoTabCompleteAction()
  if g:env_is_nvim
    " Hack nvim，nvim 中，在 DoComplete 中 mode() 会是 n，导致调用 flush()
    " nvim 中改用异步调用
    call s:AsyncRun(function('s:DoComplete'), [v:true], 1)
    call s:SendKeys( "\<ESC>a" )
  elseif g:env_is_vim
    call s:DoComplete(v:true)
  endif
endfunction

" CleverShiftTab
function! easycomplete#CleverShiftTab()
  call s:zizz()
  return pumvisible() ? "\<C-P>" : "\<Tab>"
endfunction

" <CR> 逻辑，主要判断是否展开代码片段
function! easycomplete#TypeEnterWithPUM()
  let l:item = easycomplete#GetCompletedItem()
  " 得到光标处单词
  let l:word = matchstr(getline('.'), '\S\+\%'.col('.').'c')
  " 选中目录
  if (pumvisible() && !empty(l:item) && get(l:item, "menu") ==# "[Dir]")
    call s:CloseCompletionMenu()
    call s:flush()
    call s:AsyncRun(function('s:DoComplete'), [v:true], 60)
    return "\<C-Y>"
  endif
  " 选中 snippet
  if (pumvisible() && !empty(l:item) && s:SnipSupports() &&
        \ get(l:item, "menu") ==# "[S]" )
    call s:ExpandSnipManually(get(l:item, "word"))
    call s:zizz()
    return "\<C-Y>"
  endif
  " 未选中任何单词，直接回车，直接关闭匹配菜单
  if pumvisible() && s:SnipSupports() && empty(l:item)
    call s:zizz()
    return "\<C-Y>"
  endif
  " 其他选中动作一律插入单词并关闭匹配菜单
  if pumvisible()
    call s:zizz()
    " 新增 expandable 支持 for #48
    if easycomplete#util#expandable(l:item)
      let l:back = get(json_decode(l:item['user_data']), 'cursor_backing_steps', 0)
      call s:AsyncRun(function('s:CursorExpandableSnipPosition'), [l:back], 15)
      if easycomplete#ok('g:easycomplete_signature_enable')
        call s:AsyncRun("easycomplete#action#signature#do",[], 60)
      endif
    endif
    return "\<C-Y>"
  endif
  return "\<CR>"
endfunction

function! s:CursorExpandableSnipPosition(back)
  call cursor(getcurpos()[1], getcurpos()[2] - a:back)
endfunction

function! s:ExpandSnipManually(word)
  if !exists("*UltiSnips#SnippetsInCurrentScope")
    return ""
  endif
  try
    if index(keys(UltiSnips#SnippetsInCurrentScope()), a:word) >= 0
      " 可直接展开
      call s:CloseCompletionMenu()
      call feedkeys("\<C-R>=UltiSnips#ExpandSnippetOrJump()\<cr>")
      return ""
    elseif empty(UltiSnips#SnippetsInCurrentScope())
      " 需要展开选项
      call s:CloseCompletionMenu()
      call feedkeys("\<Plug>EasycompleteExpandSnippet")
      return ""
    endif
  catch
    " https://github.com/jayli/vim-easycomplete/issues/53#issuecomment-843701311
    echom v:exception
  endtry
endfunction

function! s:SendKeys(keys)
  call feedkeys(a:keys, 'in')
endfunction

function! s:StringTrim(str)
  return easycomplete#util#trim(a:str)
endfunction

" close pum
function! s:CloseCompletionMenu()
  if pumvisible()
    silent! noa call s:SendKeys("\<C-Y>")
    call s:zizz()
  endif
  call s:ResetCompletedItem()
endfunction

function! s:CompleteHandler()
  call s:StopAsyncRun()
  if s:NotInsertMode() && g:env_is_vim | return | endif
  let l:ctx = easycomplete#context()
  " 执行 complete action 之前最后一道严格拦截，只对这四个末尾特殊字符放行
  let l:checking = [':','.','/','>']
  if &filetype == "json"
    call extend(l:checking, ['"'])
  endif
  if strwidth(l:ctx['typing']) == 0 && index(l:checking, l:ctx['char']) < 0
    return
  endif
  " 以上所有步骤都是特殊情况的拦截，后续逻辑应当完全交给 LSP 插件来做标准处
  " 理，原则上后续处理不应当做过多干扰，是什么结果就是什么结果了，除非严重错误，
  " 否则不应该在后续链路做 Hack 了
  call s:flush()
  call s:CompleteInit()
  call s:CompletorCallingAtFirstComplete()
  " 记录 g:easycomplete_firstcomplete_ctx 的时机，最早就是这里
  let g:easycomplete_firstcomplete_ctx = easycomplete#context()
endfunction

function! s:CompleteInit(...)
  if !exists('a:1')
    let l:word = s:GetTypingWord()
  else
    let l:word = a:1
  endif
  " 这会导致 pum 闪烁
  let g:easycomplete_menuitems = []
  " 用一个延时来避免闪烁
  if exists('g:easycomplete_visual_delay') && g:easycomplete_visual_delay > 0
    call timer_stop(g:easycomplete_visual_delay)
  endif
  let g:easycomplete_visual_delay = timer_start(100, function("s:CompleteMenuResetHandler"))
endfunction

function! s:CompleteMenuResetHandler(...)
  if s:NotInsertMode() | return |endif
  if !exists("g:easycomplete_menuitems") || empty(g:easycomplete_menuitems)
    call s:CloseCompletionMenu()
  endif
endfunction

function! easycomplete#CompleteAdd(menu_list, plugin_name)
  if !s:CheckCompleteTastQueueAllDone()
    if s:zizzing() | return | endif
  endif
  if s:NotInsertMode() | return |endif
  if !exists('g:easycomplete_menucache')
    call s:SetupCompleteCache()
  endif

  if !exists('g:easycomplete_menuitems')
    let g:easycomplete_menuitems = []
  endif

  if type(a:menu_list) != type([]) || empty(a:menu_list)
    if s:CheckCompleteTastQueueAllDone()
      " continue
    else
      return
    endif
  endif

  if easycomplete#CompleteCursored()
    call feedkeys("\<C-E>")
  endif

  " FristComplete 的过滤方法参照 YCM 和 coc 重写了
  " 为了避免重复过滤，去掉了这里的 CompleteMenuFilter 动作
  " 这里只做 CombineAllMenuitems 动作，在 Render 时一次性做过滤
  let typing_word = s:GetTypingWord()
  let new_menulist = a:menu_list
  let g:easycomplete_source[a:plugin_name].complete_result =
        \ deepcopy(s:NormalizeSort(s:NormalizeMenulist(a:menu_list)))
  let g:easycomplete_menuitems = s:CombineAllMenuitems()
  let g_easycomplete_menuitems = deepcopy(g:easycomplete_menuitems)
  let start_pos = col('.') - strwidth(typing_word)
  let filtered_menu = g_easycomplete_menuitems

  try
    call s:FirstComplete(start_pos, filtered_menu)
  catch /^Vim\%((\a\+)\)\=:E730/
    return v:null
  endtry
  if g:env_is_vim
    call easycomplete#popup#close("popup")
  endif
endfunction

function! s:EchoLspMenuItems()
  let ret = []
  for item in g:easycomplete_menuitems
    if item.menu == "[TS]"
      call add(ret, item.word)
    endif
  endfor
  return ret
endfunction

function! s:CombineAllMenuitems()
  let result = []
  for name in keys(g:easycomplete_source)
    call extend(result, get(g:easycomplete_source[name], 'complete_result', []))
  endfor
  return result
endfunction

function! s:FirstComplete(start_pos, menuitems)
  if s:zizzing() | return | endif
  if s:CheckCompleteTastQueueAllDone()
    call s:FirstCompleteRendering(a:start_pos, a:menuitems)
  endif
endfunction

function! easycomplete#GetOptions(name)
  return get(g:easycomplete_source, a:name, {})
endfunction

function! easycomplete#FirstCompleteRendering(...)
  return call("s:FirstCompleteRendering", a:000)
endfunction

function! easycomplete#GetPlugNameByCommand(cmd)
  let plug_name = ""
  for name in keys(g:easycomplete_source)
    if a:cmd == get(g:easycomplete_source[name], 'command', '')
      let plug_name = name
      break
    endif
  endfor
  return plug_name
endfunction

function! s:FirstCompleteRendering(start_pos, menuitems)
  if easycomplete#util#NotInsertMode()
    call s:flush()
    return
  endif
  let typing_word = s:GetTypingWord()
  let should_stop_render = 0
  try
    if s:OrigionalPosition()
      " 如果 LSP 结果返回时没有前进 typing，就返回结果过滤呈现即可
      let source_result = a:menuitems
    elseif !empty(typing_word) && easycomplete#context()["typed"] =~ "[a-zA-Z0-9#]$"
      " FirstTyping 已经发起 LSP Action，结果返回之前又前进 Typing，直接执行
      " easycomplete#typing() → s:CompleteTypingMatch()，叠加之前请求 LSP 的返
      " 回值后进行重新过滤呈现
      let source_result = a:menuitems + g:easycomplete_stunt_menuitems
    else
      if !pumvisible()
        let should_stop_render = 1
      endif
    endif

    if !should_stop_render && len(source_result) > 0
      let filtered_menu = easycomplete#util#CompleteMenuFilter(source_result, typing_word, 600)
      let filtered_menu = easycomplete#util#distinct(deepcopy(filtered_menu))
      let filtered_menu = map(filtered_menu, function("easycomplete#util#PrepareInfoPlaceHolder"))
      let g:easycomplete_stunt_menuitems = filtered_menu
      let result = filtered_menu[0 : g:easycomplete_maxlength]
      if len(result) <= 10
        let result = easycomplete#util#uniq(result)
      endif
      " Info: 调用 complete 有两种方法
      "    第一种是直接执行 complete, complete(a:start_pos, result)
      "    第二种是通过<Plug>Complete,easycomplete#_complete(a:start_pos, result)
      " 第一种优势是不会造成 mode() 的切换，避免 CmdlineEnter 和 CmdlineLeave
      " 事件发生，杜绝 statusline 的闪烁，缺点是不通过cmd队列来显示的话，容易
      " 在连续快速敲击键盘时渲染菜单动作的进程挤占，带来不必要的菜单render视觉破损
      " 第二种优势是通过事件队列来管理，菜单高速连续切换显示时比较流畅，但在首
      " 次FirstComplete当匹配菜单内容过大、计算量过重时，带来的延时会造成明显
      " 的 CmdlineEnter 和 CmdlineLeave，带来 statusline 闪烁。
      " 因此在 FirstComplete 时采用方法一，SecondComplete 采用方法二
      call s:complete(a:start_pos, result)
      call s:SetFirstCompeleHit()
      call s:AddCompleteCache(s:GetTypingWord(), deepcopy(g:easycomplete_stunt_menuitems))
    endif
    if s:first_render_timer > 0
      call timer_stop(s:first_render_timer)
      let s:first_render_timer = 0
    endif
    call s:LetCompleteTaskQueueAllDone()
  catch
    echom v:exception
  endtry
endfunction

function! easycomplete#refresh(...)
  let start = get(g:easycomplete_complete_ctx, 'start', col('.'))
  let candidates = get(g:easycomplete_complete_ctx, 'candidates', [])
  noa call s:complete(start, candidates)
  return ''
endfunction

function! s:complete(start, context) abort
  noa silent! call complete(a:start, a:context)
  noa call easycomplete#popup#overlay()
endfunction

" Alias of complete()
function! easycomplete#_complete(start, items)
  let g:easycomplete_complete_ctx = {
        \ 'start': a:start,
        \ 'candidates': a:items,
        \}
  if mode() =~# 'i' && &paste != 1
    silent! noa call feedkeys("\<Plug>EasycompleteRefresh", 'i')
  endif
endfunction

function! s:SetFirstCompeleHit()
  let g:easycomplete_first_complete_hit = 1
endfunction

function! s:emit(...)
  return call("easycomplete#util#emit", a:000)
endfunction

" TODO 性能优化，4 次调用 0.08 s
" TODO PY 和 VIM 实现的一致性
" 因为需要对全量列表进行排序，所以只在 FirstComplete 之前的数据准备时使用
function! s:NormalizeSort(items)
  if has("python3")
    return s:NormalizeSortPY(a:items)
  else
    return s:NormalizeSortVIM(a:items)
  endif
endfunction

function! s:NormalizeSortVIM(items)
  " 先按照长度排序
  let l:items = sort(copy(a:items), "s:SortTextComparatorByLength")
  " 再按照字母表排序
  let l:items = sort(copy(l:items), "s:SortTextComparatorByAlphabet")
  return l:items
endfunction

function! s:NormalizeSortPY(...)
  return call("easycomplete#python#NormalizeSortPY", a:000)
endfunction

function! s:SortTextComparatorByAlphabet(...)
  return call("easycomplete#util#SortTextComparatorByAlphabet", a:000)
endfunction

function! s:SortTextComparatorByLength(...)
  return call("easycomplete#util#SortTextComparatorByLength", a:000)
endfunction

function! s:NormalizeMenulist(arr)
  if empty(a:arr)
    return []
  endif
  let l:menu_list = []

  for item in a:arr
    if type(item) == type("")
      let l:menu_item = {
            \ 'word': item,    'menu': '',
            \ 'user_data': '', 'info': '',
            \ 'kind': '',      'equal' : 1,
            \ 'dup': 1,        'abbr': '',
            \ 'kind_number' : get(item, 'kind_number', 0),
            \ }
      call add(l:menu_list, l:menu_item)
    endif
    if type(item) == type({})
      call add(l:menu_list, extend({
            \   'word': '',      'menu': '',
            \   'user_data': '', 'equal': 1,
            \   'dup': 1,        'info': '',
            \   'kind': '',      'abbr': '',
            \   'kind_number' : get(item, 'kind_number', 0),
            \ },  item ))
    endif
  endfor
  return l:menu_list
endfunction

function! s:CompleteAdd(...)
  return call("easycomplete#CompleteAdd", a:000)
endfunction

function! s:CompleteFilter(raw_menu_list)
  let arr = []
  let word = s:GetTypingWord()
  if empty(word)
    return a:raw_menu_list
  endif
  for item in a:raw_menu_list
    if strwidth(matchstr(item.word, word)) >= 1
      call add(arr, item)
    endif
  endfor
  return arr
endfunction

"  TaskQueue: 每个插件都完成后，一并显示匹配菜单
"  任务队列的设计不完善，当lsp特别慢的时候有可能会等待很长时间，需要加一个超时
"
" FirstComplete 过程中调用
function! s:ResetCompleteTaskQueue()
  let g:easycomplete_complete_taskqueue = []
  let l:ctx = easycomplete#context()
  for name in keys(g:easycomplete_source)
    if s:CompleteSourceReady(name) && (s:NormalTrigger() || s:SemanticTriggerForPluginName(name))
      call s:SetCompleteTaskQueue(name, l:ctx, 1, 0)
    else
      call s:SetCompleteTaskQueue(name, l:ctx, 0, 0)
    endif
  endfor
endfunction

" SecondComplete 过程中调用
function! s:ResetAlwaysCompleteTaskQueue()
  let g:easycomplete_complete_taskqueue = []
  let l:ctx = easycomplete#context()
  for name in keys(g:easycomplete_source)
    if s:CompleteSourceReady(name) && get(g:easycomplete_source[name], 'trigger', '') == 'always'
      call s:SetCompleteTaskQueue(name, l:ctx, 1, 0)
    elseif s:CompleteSourceReady(name)
      call s:SetCompleteTaskQueue(name, l:ctx, 1, 1)
    else
      call s:SetCompleteTaskQueue(name, l:ctx, 0, 0)
    endif
  endfor
endfunction

function! s:SetCompleteTaskQueue(name, ctx, condition, done)
  call filter(g:easycomplete_complete_taskqueue, 'v:val.name != "'.a:name.'"')
  call add(g:easycomplete_complete_taskqueue, {
        \ "name" : a:name,
        \ "condition": a:condition,
        \ "ctx" : a:ctx,
        \ "done" : a:done
        \ })
endfunction

function! s:CheckCompleteTastQueueAllDone()
  let flag = v:true
  for item in g:easycomplete_complete_taskqueue
    if item.condition == 1 && item.done == 0
      let flag = v:false
      break
    endif
  endfor
  return flag
endfunction

function! s:complete_check()
  return !s:CheckCompleteTastQueueAllDone()
endfunction

function! s:LetCompleteTaskQueueAllDone()
  for item in g:easycomplete_complete_taskqueue
    let item.done = 1
  endfor
endfunction

function! easycomplete#AutoLoadDict()
  call easycomplete#util#AutoLoadDict()
endfunction

function! s:SnipSupports()
  if !has("python3")
    return v:false
  endif
  try
    call funcref("UltiSnips#RefreshSnippets")
  catch /^Vim\%((\a\+)\)\=:E700/
    return v:false
  endtry
  return v:true
endfunction

function! easycomplete#nill() abort
  return ''
endfunction

function! easycomplete#GetStuntMenuItems()
  return g:easycomplete_stunt_menuitems
endfunction

" 清空全局配置
function! s:flush()
  let g:easycomplete_menuitems = []
  let g:easycomplete_stunt_menuitems = []
  let g:easycomplete_first_complete_hit = 0
  call s:ResetCompletedItem()
  call s:ResetCompleteCache()
  call s:ResetCompleteTaskQueue()
  let g:easycomplete_firstcomplete_ctx = {}
  let b:typing_ctx = easycomplete#context()
  let g:easycomplete_completechanged_event = {}
  if s:first_render_timer > 0
    call timer_stop(s:first_render_timer)
    let s:first_render_timer = 0
  endif
  for sub in keys(g:easycomplete_source)
    let g:easycomplete_source[sub].complete_result = []
  endfor
  let g:easycomplete_completedone_insert_mode = mode()
  if easycomplete#util#InsertMode() && complete_check()
    call s:StopAsyncRun()
    call s:AsyncRun(function("complete"),[col("."),[]],50)
  endif
endfunction

function! s:ResetCompletedItem()
  if pumvisible()
    return
  endif
  let g:easycomplete_completed_item = {}
endfunction

function! s:SetupCompleteCache()
  let g:easycomplete_menucache = {}
  let g:easycomplete_menucache["_#_1"] = 1  " line num of current typing word
  let g:easycomplete_menucache["_#_2"] = 1  " col num of current typing word
endfunction

function! s:ResetCompleteCache()
  if !exists('g:easycomplete_menucache') || empty(get(g:easycomplete_menucache, "_#_1"))
    call s:SetupCompleteCache()
  endif

  let start_pos = col('.') - strwidth(s:GetTypingWord())
  if g:easycomplete_menucache["_#_1"] != line('.') || g:easycomplete_menucache["_#_2"] != start_pos
    let g:easycomplete_menucache = {}
  endif
  let g:easycomplete_menucache["_#_1"] = line('.')  " line num
  let g:easycomplete_menucache["_#_2"] = start_pos  " col num
endfunction

function! s:AddCompleteCache(word, menulist)
  if !exists('g:easycomplete_menucache')
    call s:SetupCompleteCache()
  endif

  let start_pos = col('.') - strwidth(a:word)
  if g:easycomplete_menucache["_#_1"] == line('.') && g:easycomplete_menucache["_#_2"] == start_pos
    let g:easycomplete_menucache[a:word] = a:menulist
  else
    let g:easycomplete_menucache = {}
  endif
  let g:easycomplete_menucache["_#_1"] = line('.')  " line num
  let g:easycomplete_menucache["_#_2"] = start_pos  " col num
endfunction

function! s:GetCompleteCache(word)
  return {'menu_items':get(g:easycomplete_menucache, a:word, []),
        \ 'start_pos':g:easycomplete_menucache["_#_2"]
        \ }
endfunction

function! easycomplete#GetCompleteCache(...)
  return call("s:GetCompleteCache", a:000)
endfunction

function! s:ResetBacking(...)
  let g:easycomplete_backing_or_cr = 0
endfunction

" 空闲 30ms，简单粗暴避免事件意外触发
function! s:zizz()
  let delay = g:env_is_nvim ? 30 : (&filetype == 'vim' ? 50 : 50)
  let g:easycomplete_backing_or_cr = 1
  if exists('s:zizz_timmer') && s:zizz_timmer > 0
    call timer_stop(s:zizz_timmer)
  endif
  let s:zizz_timmer = timer_start(delay, function('s:ResetBacking'))
  return "\<BS>"
endfunction

function! s:StopZizz()
  if exists('s:zizz_timmer') && s:zizz_timmer > 0
    call timer_stop(s:zizz_timmer)
  endif
  call s:ResetBacking()
endfunction

function s:zizzing()
  return g:easycomplete_backing_or_cr == 1 ? v:true : v:false
endfunction

function! s:SameCtx(ctx1, ctx2)
  if !has_key(a:ctx1, 'lnum') || !has_key(a:ctx2, 'lnum')
    return v:false
  endif
  if a:ctx1["lnum"] == a:ctx2["lnum"]
        \ && a:ctx1["col"] == a:ctx2["col"]
        \ && a:ctx1["typing"] ==# a:ctx2["typing"]
    return v:true
  else
    return v:false
  endif
endfunction

function! easycomplete#SameBeginning(ctx1, ctx2)
  return s:SameBeginning(a:ctx1, a:ctx2)
endfunction

" ctx1 在前，ctx2 在后
" 判断 FirstComplete 和 SecondComplete 是否是一个 ctx 下的行为
function! s:SameBeginning(ctx1, ctx2)
  try
    if !has_key(a:ctx1, "lnum") || !has_key(a:ctx2, "lnum")
      return v:false
    endif
  catch
    " for E715
    return v:false
  endtry
  if a:ctx1["startcol"] == a:ctx2["startcol"]
        \ && a:ctx1["lnum"] == a:ctx2["lnum"]
        \ && match(a:ctx2["typing"], a:ctx1["typing"]) == 0
    return v:true
  else
    return v:false
  endif
endfunction

function! s:GetTypingWord()
  return easycomplete#util#GetTypingWord()
endfunction

function! s:HasKey(...)
  return call('easycomplete#util#HasKey', a:000)
endfunction

function! s:AsyncRun(...)
  return call('easycomplete#util#AsyncRun', a:000)
endfunction

function! s:StopAsyncRun(...)
  return call('easycomplete#util#StopAsyncRun', a:000)
endfunction

function! s:NotInsertMode()
  return call('easycomplete#util#NotInsertMode', a:000)
endfunction

function! s:log(...)
  return call('easycomplete#util#log', a:000)
endfunction

function! s:console(...)
  return call('easycomplete#log#log', a:000)
endfunction

function! s:trace(...)
  return call('easycomplete#util#trace', a:000)
endfunction

function! Console(...)
  return call('easycomplete#log#log', a:000)
endfunction

" LSP 的 completor 函数，通用函数，可以直接使用，也可以自己再封装一层
function! easycomplete#DoLspComplete(opt, ctx)
  return easycomplete#action#completion#do(a:opt, a:ctx)
endfunction

" LSP definition 跳转的通用封装
" file_exts 文件后缀
function! easycomplete#DoLspDefinition(file_exts)
  let ext = tolower(easycomplete#util#extention())
  if index(a:file_exts, ext) >= 0
    return easycomplete#action#defination#LspRequest()
  endif
  " exec "tag ". expand('<cword>')
  " 未成功跳转，则交给主进程处理
  return v:false
endfunction

" lsp 各项配置检查是否通过
function! easycomplete#ok(str)
  let varstr = substitute(a:str, "[abvgsl]:","","i")
  let flag = v:false
  let value = get(g:easycomplete_config, a:str, 0)
  if exists(a:str) && get(g:, varstr, 0) == 0
    let flag = v:false
  elseif exists(a:str) && get(g:, varstr, 0) != 0
    let flag = get(g:, varstr, 0)
  elseif !exists(a:str)
    let flag = value
  endif
  let g:easycomplete_config[a:str] = flag
  return flag
endfunction

" v:true 立即渲染，v:false 延时渲染
function! easycomplete#lint()
  call easycomplete#action#diagnostics#do()
endfunction

function! easycomplete#BufWritePost()
  call easycomplete#lint()
endfunction

function! easycomplete#CursorMoved()
  if easycomplete#ok('g:easycomplete_diagnostics_enable')
        \ && easycomplete#util#NormalMode()
    call easycomplete#sign#LintCurrentLine()
  endif
endfunction

function! easycomplete#CursorMovedI()
endfunction

function! easycomplete#defination()
  call easycomplete#action#defination#do()
endfunction

" for 外部调用
function! easycomplete#signature()
  if easycomplete#ok('g:easycomplete_signature_enable')
    call easycomplete#action#signature#do()
  endif
  return ""
endfunction

function! easycomplete#CursorHold()
  if easycomplete#ok('g:easycomplete_diagnostics_enable')
        \ && easycomplete#ok('g:easycomplete_diagnostics_hover')
    call easycomplete#sign#LintPopup()
  endif
endfunction

function! easycomplete#TextChangedI()
  call easycomplete#typing() " for completion
  if easycomplete#ok('g:easycomplete_signature_enable')
    call easycomplete#action#signature#handle()
  endif
  let b:old_changedtick = b:changedtick
  return ""
endfunction

function! easycomplete#TextChangedP()
  let l:ctx = easycomplete#context()
  let line_length = strlen(l:ctx['typed'])
  let selected_item = easycomplete#GetCompletedItem()
  if empty(selected_item)
    let word_str_len = 0
  else
    let word_str_len = strlen(selected_item["word"])
  endif
  if b:old_changedtick == b:changedtick
    " 在 FristComplete 时，TextChangedI 触发后会执行 complete()，还会触发一次
    " TextChangedP，如果两个事件的 changedtick 相同，则丢弃 TextChangedP 事件
  elseif easycomplete#CompleteCursored() &&
        \ easycomplete#GetCompletedItem()["word"] == l:ctx['typed'][line_length - word_str_len:line_length - 1]
    " 直接按下 C-P 或者 C-N 不做任何处理
  elseif pumvisible() && !s:zizzing()
    " 再次确保这里的逻辑要躲过 FirstComplete
    " 同时判断是否已经发生过了 firstCompleteHit
    " 目的仍然是避免FirstComplete的重复渲染
    if s:OrigionalPosition() || g:easycomplete_first_complete_hit != 1
      return
    endif
    let g:easycomplete_start = reltime()
    let delay = len(g:easycomplete_stunt_menuitems) > 180 ?
          \ (g:env_is_iterm && g:env_is_vim ? 35 : (g:env_is_nvim ? 10 : 20)) : (has("nvim") ? 2 : 4)
    call s:StopAsyncRun()
    " 异步执行的目的是避免快速频繁输入字符时的complete渲染扎堆带来的视觉破损，
    " 不能杜绝，但能大大缓解
    call s:AsyncRun(function('s:CompleteMatchAction'), [], delay)
    let b:old_changedtick = b:changedtick
  endif
endfunction

function! easycomplete#CmdlineEnter()
endfunction

function! easycomplete#CmdlineLeave()
endfunction

function! easycomplete#Textchanged()
endfunction

function! easycomplete#InsertEnter()
  call easycomplete#sign#DiagHoverFlush()
endfunction

function! easycomplete#BufEnter()
  if easycomplete#ok('g:easycomplete_diagnostics_enable')
    call timer_start(1600, { -> easycomplete#lint() })
  endif
endfunction

