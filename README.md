### 配环境
#### BIDs 支持
```
uv tool install dcm2niix
uv tool install dcm2bids
```
这会在一个隔离的、受保护的地方为 dcm2bids 创建环境，并把命令软链接到你的系统路径。你以后在任何文件夹下直接输入 dcm2bids 都能用，就像安装了一个原生软件一样。  
#### hd-bet 安装
运行`uv tool install hd-bet`
#### FASTSURFER 安装
```
CURRDIR=$(pwd)
cd $HOME/FastSurfer
source .venv/bin/activate
cd $CURRDIR
```
