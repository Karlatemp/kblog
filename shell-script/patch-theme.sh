if [ $OS == 'Windows_NT' ]; then
    shell-script/patch-windows.cmd
    exit 0
else
    ln -s t-layouts node_modules/hexo-theme-butterfly/layout/kar
fi