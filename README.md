# 浙大启真低空侦测与安全运营平台

本项目包含面向企业级方案汇报的低空侦测与安全运营平台可视化页面、架构图和相关文档。

## 目录结构说明

- `浙大启真低空侦测与安全运营平台_企业级系统架构图.html`：企业级架构图演示页面
- `低空数字孪生平台1.0需求规格说明书（一期二期细化版）.md`：需求规格说明书
- `低空侦测招投标案例库_120条.csv`：招投标案例数据
- `部署说明.md`：项目部署指南
- 其他 HTML/MD/PPTX 文件：项目展示与方案材料

## 快速部署到 GitHub

在 PowerShell 中运行以下命令：

```powershell
cd "d:\00在建项目\02低空数字孪生平台建设"
git init
git add .
git commit -m "Add 浙大启真低空侦测与安全运营平台 project"
```

然后在 GitHub 上创建一个仓库，复制仓库地址后运行：

```powershell
git remote add origin https://github.com/你的账号/仓库名.git
git branch -M main
git push -u origin main
```

如果已经添加过远程仓库，可以改成：

```powershell
git remote set-url origin https://github.com/你的账号/仓库名.git
git push -u origin main
```

## 备注

- 请确保 Git 安装成功并已重启终端
- 若使用 GitHub CLI，可通过 `gh repo create` 快速创建仓库
- 本项目适用于直接作为方案汇报页面和可视化展示材料
