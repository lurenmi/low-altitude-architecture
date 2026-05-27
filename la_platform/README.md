# 低空数字孪生平台（本地全栈版）

本版本落地三大板块，并补齐生产化交互能力：

1. 低空一张图：图层、检索、地图对象编辑（新建/更新/删除）、编辑留痕。
2. 飞行服务：飞行计划、审批流转、风险校验、审批规则可配置、任务回放。
3. 空域设施：空域管制区、网格容量、设施资源、微气象和数据底座来源。

## 目录

```text
la_platform/
  backend/
    schema.sql
    init_db.py
    api_server.py
  frontend/
    index.html
    styles.css
    app.js
  data/
    hangzhou_seed.json
    hangzhou_seed_sources.md
  启动平台.ps1
```

## 一键启动

```powershell
powershell -ExecutionPolicy Bypass -File .\la_platform\启动平台.ps1
```

访问：

```text
http://localhost:8090/
```

## 新增核心接口

- 审批规则
  - `GET /api/v1/flight/approval-rules`
  - `POST /api/v1/flight/approval-rules`
- 地图编辑
  - `POST /api/v1/map/objects`
  - `PUT /api/v1/map/objects/{object_code}`
  - `DELETE /api/v1/map/objects/{object_code}`
  - `GET /api/v1/map/edit-records`
- 任务回放
  - `GET /api/v1/flight/plans/{id}/replay`
  - `POST /api/v1/flight/plans/{id}/replay/generate`
- 空域可视化
  - `GET /api/v1/airspace/visualization`
  - 前端使用 Three.js 渲染 3D 体素场景（空域/网格/设施/气象）

## 数据库新增表

- `approval_rule_sets`
- `approval_rule_logs`
- `map_edit_records`
- `flight_replay_tracks`

## 备注

- `init_db.py` 每次执行会重建种子数据，并初始化审批规则和回放轨迹。
- 杭州样例数据来源见 `data/hangzhou_seed_sources.md`。
