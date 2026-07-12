" Vim is based on Vi. Setting `nocompatible` switches from the default
" Vi-compatibility mode and enables useful Vim functionality.
set nocompatible

" Turn on syntax highlighting.
syntax on

" Disable the default Vim startup message.
set shortmess+=I

" Show line numbers.
set number

" Set system clipboard as the default register
set clipboard=unnamed

" Always show the status line at the bottom, even if you only have one window open.
set laststatus=2

" Backspace behave more reasonably.
set backspace=indent,eol,start

" Enable hidden buffers.
set hidden

" Search case-insensitive when all characters in search are lowercase.
set ignorecase
set smartcase

" Enable searching as you type.
set incsearch

" Unbind Ex mode.
nmap Q <Nop>

" Disable audible bell.
set noerrorbells visualbell t_vb=

" Enable mouse support.
set mouse+=a

" Allow using jj to exit INSERT mode.
inoremap jj <ESC>

" Termguicolors setup
if (has('termguicolors'))
  set termguicolors
endif

" Fix italics in Vim
if !has('nvim')
  let &t_ZH="\e[3m"
  let &t_ZR="\e[23m"
endif

let g:material_terminal_italics = 1
let g:onedark_terminal_italics = 1
let g:material_theme_style = 'onedark'
colorscheme onedark
