# 自建 Sports

在 Sapphire 公开源码版中加入独立实现的运动比分、F1 排名和赛程，入口为 **Settings → Sports**。这一页可选择赛事、关注球队／车手／车队，也可开启刘海中的 Sports widget、F1 排名和足球比分活动。它没有依赖作者未公开的商业模块。

## 内容

- Formula 1：**Live timing** 页显示数据源最新公布的排名、比赛圈数、可用的车手已完成圈数及退赛状态；**Race calendar** 保留所选赛季赛历和已公布赛后成绩。历史比赛可点击 **Load results**。
- 足球：英超、欧冠、西甲、意甲、德甲、法甲、MLS。可切换日期查看赛程、比赛中比分、完场成绩，关注球队后用 **Following** 筛选。
- 未开始的比赛不显示虚构比分。无比赛、断网、接口错误和缓存数据都有对应状态与重试入口。
- 日期按本机时区显示。足球页面打开时每分钟刷新。F1 赛中约每 15 秒请求更新，非比赛时约每分钟检查；数据源本身可能延迟，并非无延迟遥测。缺失的圈数显示破折号，不推算差距；断网或过期数据会明确标注，过期排名不继续作为刘海实时活动显示。

## 设置与使用

1. 先退出旧版 Sapphire，再打开 `output/Sapphire Click.app`。
2. 在 **Settings → Sports** 打开页面，选择 Formula 1 或足球赛事。
3. 打开 **Show Sports widget in the notch** 后，可由刘海 Sports 小组件进入完整页面。
4. F1 的 **Show live positions and lap count** 控制比赛进行中的刘海活动。**Driver in the notch** 可指定车手；自动模式优先关注车手、关注车队中的车手，最后使用领先车手。收起时显示圈数和该车手位置，点击展开排名表。
5. F1 设置中的星标分别关注车手和车队；排名行的星标可单独关注车手。足球仍在球队列表关注，用 **Following** 筛选。
6. **Show live football scores** 控制足球比分活动，**Only show matches while live** 可只显示比赛进行中的内容。

足球数据读取 [ESPN 的公开记分板](https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard)，F1 当前场次和排名使用 [ESPN F1 记分板](https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard)及对应场次详情；F1 赛历与赛后成绩读取 [Jolpica F1](https://api.jolpi.ca/ergast/f1/2026/)（[接口文档](https://github.com/jolpica/jolpica-f1/blob/main/docs/README.md)）。当前实现无需填写 API key，页面提供原赛事链接。它是 Sapphire 中参考运动比分应用使用方式的新实现，不连接 Apple Sports 账户。

## 验证

```sh
bash Tools/CommunitySportsTests/run.sh
bash Tools/CommunitySportsTests/run.sh --live
bash Tools/F1LiveTests/run.sh
bash Tools/F1LiveTests/run.sh --live
bash Tools/F1LiveTests/render.sh
```

离线测试覆盖比赛状态与空比分、主客队顺序、赛历与公布成绩、收藏持久化、离线缓存、异步切换、缓存与并发合并、旧接口适配，以及自建 Sports／Finance 的四个功能入口。F1 另覆盖练习／进行中／完场／缺失圈数／过期、关注项持久化、请求上限与取消、非比赛周末名单。`--live` 使用实际 URLSession 请求数据源；本次验证了当前场次及历史新加坡站 22 位车手、62 圈成绩。排名表另通过 500／590 宽度的浅色、深色和过期状态离屏渲染。尚未在真实比赛期间完整操作刘海进行验收。

实现位于 `Sapphire/Services/CommunitySports/` 和 `Sapphire/Widgets/CommunitySports/`。原有 Sports 占位视图和服务现在转接这些实现。其他未公开商业模块不受影响。
