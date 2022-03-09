echo "$OS"
if [ "$OS" == 'Windows_NT' ]; then
    echo Patching via Windows
    shell-script/patch-windows.cmd
    exit 0
else
    echo Patching via Linux
    p=`readlink -f t-layouts`
    ln -s "$p" node_modules/hexo-theme-butterfly/layout/kar
fi