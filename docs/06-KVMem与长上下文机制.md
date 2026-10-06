# 06 · KVMem 与长上下文机制

> 这一篇解释"为什么同一会话第二轮会秒回"、"为什么材料太长会静默漏掉中间"，
> 以及**日志里那几百行重复的行到底在说什么**。

---

## 1. 三层结构

```text
             ┌─────────────────────────────────────────────┐
   显存      │  设备 KV 池  4,032 token（63 页 / 共 1,024 页）│  ← 常驻，最快
             └─────────────────────────────────────────────┘
                              ↕ 换页
             ┌─────────────────────────────────────────────┐
   内存      │  主机 KV 层  4.00 GiB（钉住，不换出）          │  ← 放不下的 KV 挪到这里
             └─────────────────────────────────────────────┘
```

| 概念       | 实测值                  | 说明                           |
| ---------- | ----------------------- | ------------------------------ |
| 页（page） | **1 页 = 64 token**     | 换页与打分的最小单位           |
| 设备 KV 池 | **4,032 token = 63 页** | 显存里常驻的部分               |
| 页表容量   | **1,024 页**            | 池结构的上限                   |
| 主机 KV 层 | **4.00 GiB**            | 钉在内存里（`host KV pinned`） |

> **"超池"的定义**：题面 token 数 > 设备池 token 数。
> 一旦超池，引擎会打一行告警，且**部分内容不在常驻区**。

---

## 2. 环（ring）的六个开关

```bat
set "NINFER_KV_WINDOW=16384"        REM 检索窗口
set "NINFER_KV_RETRIEVE=8192"       REM 检索深度
set "NINFER_KV_RING=1"              REM 环式复用总开关
set "NINFER_HOST_PAGEABLE=1"        REM 允许把页挪到主机层
set "NINFER_KV_REUSE_HOSTBACKED=1"  REM 允许复用主机层里的页
set "NINFER_TERNARY_PTQ1_FAST=1"    REM PTQ1 档快速路径
```

**这六个必须同时成立**，否则环不工作。其中 `NINFER_KV_RETRIEVE` 尤其不能删——
上游记录过去掉它会让检索**静默答错**（不报错，只是答案变差）。

启动后应当看到这两行作为"环已生效"的证据：

```text
[ninfer] reuse host-backed: on
[ring] content scoring ON by default (the ring is configured): retrieval ranks pages by
        the query-conditioned content score. ...
```

---

## 3. 内容打分（content scoring）

**核心机制**：检索不再按"最近用过"排序，而是**按"与当前问题的相关度"给页打分**，再把高分页搬回显存。

**关键细节：查询用的是"最后一条用户消息"。**

| 最后一条消息长度 | 行为                                            |
| ---------------- | ----------------------------------------------- |
| **≤ 256 token**  | ✅ 正常按内容打分                               |
| **> 256 token**  | ❌ 打分**整体失效**，退化为"只看结尾"的尾部规则 |

退化时日志会打印（**但不会报错**）：

```text
kvmem_score: query span [58855,58934) not usable for chunk [0,1024)
             (empty overlap or longer than MAXQ=256) -- falling back to the tail rule (QUERY_TAIL)
kvmem_score: KEPT 0
```

> **实用结论（本方案最重要的一条使用纪律）**：
> **长材料放前面的消息里，最后一条提问写短（≤256 token）。**

---

## 4. 前缀复用（"第二轮秒回"的原理）

同一个会话里，前面的内容不必重算——环把它们的 KV 保留下来，下一轮直接接着用。

**实测**：

| 轮次    | prompt | 命中缓存          | TTFT       |
| ------- | ------ | ----------------- | ---------- |
| 第 1 轮 | 4,049  | 0                 | 6,272 ms   |
| 第 2 轮 | 4,104  | **4,061 = 99.0%** | **254 ms** |

**能证明复用生效的是 `cache` 百分比与 TTFT 下降**，不是某一行日志。

> ⚠️ 注意 `publish host-backed: ...` 与 `adopt host-backed: ...` 这两行**不能当复用证据**：
> 前者是无条件行为，后者只说明"采纳了主机层"。

---

## 5. 日志里那几百行重复的行在说什么

当题面很长（例如 58,941 token）时，引擎会把它切成 **1,024 token 一块**依次处理，
**每一块都打印一遍同一组记账行**。58,941 ÷ 1,024 ≈ 58 块 ⇒ 几百行看着一模一样。

| 行                                                                | 含义                                                 | 危险吗          |
| ----------------------------------------------------------------- | ---------------------------------------------------- | --------------- |
| `[ninfer] ring retrieve: which=text preferred=31 restored=31 ...` | 从主机层搬回了多少页                                 | 否              |
| `kvmem_score: KEPT 0 1 2 3 ...`                                   | 这次保留哪些页（列表会越来越长）                     | 否              |
| `kvmem_score: SELECT ... kept=512 scored_kept=448 candidates=560` | 打分明细（`scored_kept` 从 0 涨到几百 = 打分在工作） | 否              |
| `[ninfer] mask hidden: ... mid_hidden=224 ...`                    | 哪些页这次"看不见"                                   | 否              |
| `[ninfer] demote-other short: freed=0 want=32 ...`                | 换页记账                                             | 否（但见下）    |
| `prompt exceeds the resident Device KV pool ...`                  | **超池告警**                                         | ✅ **是**       |
| `query span ... falling back to the tail rule`                    | **检索退化**                                         | ✅ **是**       |
| `worker crash: Paged KV reservation invariant was violated`       | **引擎已死，此后全 503**                             | ✅✅ **最危险** |

> `demote-other short` 行里如果出现 `partial=1` 之类的非零值，是**崩溃前兆的签名**，
> 值得留意（本机在压力测试里见过 11 行这样的前兆，但引擎没有崩）。

---

## 6. 超池时会发生什么

1. 引擎打印告警：

```text
[warning] ninfer-serve: prompt exceeds the resident Device KV pool:
          prompt 58941 tokens (921 pages) > pool 4032 tokens (63 pages).
          Part of the prompt is therefore not resident, and the MIDDLE of such a prompt
          has been measured to go missing with no error line, HTTP 200 and a plausible
          wrong answer; the root cause is not localized.
```

2. 检索接手：把相关页从主机层搬回设备池（所以**不一定出错**）
3. 但**中段有静默丢失的实测记录** ⇒ **这条请求的答案不能当作"它读过了全文"**

**实用判据**：

| 材料规模        | 可靠性             | 做法                       |
| --------------- | ------------------ | -------------------------- |
| ≤ 3,500 token   | 最高（全在设备池） | 直接贴、直接问             |
| 4,000 ~ 20,000  | 中                 | 两轮法 + 要求引用原文      |
| 20,000 ~ 60,000 | 低                 | 先分块摘要，再基于摘要提问 |
| > 60,000        | 不支持             | 必须分块                   |

---

## 7. 三个"知道了能少踩坑"的细节

### 7.1 层 0 有一段 KV 永远不进索引

日志每次启动都会打：

```text
[ninfer] kvmem harvest: fused rmsnorm+rope branch cannot expose the pre-RoPE key
         (layer 0, N tokens); this chunk is NOT in the index
```

这是**已知的设计后果**（融合算子拿不到 RoPE 之前的 key），不是故障。
**实践含义**：关键内容别说一遍就指望它记住；重要的事换个说法重申一次。

### 7.2 跨页缝截断

关键字符串如果正好跨在两页（64 token）交界处，有被切一半的已知记录。处置：**换个问法重问一次**。

### 7.3 冷预填可能被连接层掐断

预填超过约 2 分钟时，有被连接层断开的记录（根因未定位）。缓解：客户端超时设 ≥300 秒 + 材料分块。

---

## 8. 一句话总结

> **设备池是"桌面"，主机层是"书柜"，内容打分是"按你最后问的那句话去书柜里找书"。
> 你最后那句话太长，找书的人就罢工了——他只会把书柜最外面那几本拿给你。**

---

> 最后更新：2026-10-06
