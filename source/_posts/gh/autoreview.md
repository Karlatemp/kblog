---
title: GitHub PullRequest 自动审核合并
categories: [github]
tags: [github, pr, review]
date: 2022-02-23 00:01:00
---


众所周知, github actions 可以完成很多自动化任务, 比如代码持续CI, 版本发布自动化, new issue 内容检查等.

当然，github actions 也可以用作 PR 自动审查合并, 不过, 要完成这些需要一些额外的配置..

--------

首先需要知道的是, `on: pull_request` 的 workflow 是只有 `readonly` 的权限的, 这也就意味着通过 `on: pull_request` 发起的 workflow 除了读取已公开的内容之外什么都干不了. 包括访问 `${{ secrets.XXXX }}` 也是不被允许的

需要完成自动合并, 需要更高权限(也意味着更危险的) workflow, [pull_request_target](https://docs.github.com/en/actions/learn-github-actions/events-that-trigger-workflows#pull_request_target)

`pull_request_target` 与 `pull_request` 的用法基本一致, 但是主要有以下的区别

`actions/checkout@v2` 会签出到被 PR 的分支(也就是源仓库的内容), 而不是经过 PR 修改后的内容

`pull_request_target` 拥有 write 权限, 可以写入源仓库, 访问 `${{ secrets.XXX }}` (这是 `pull_request` 所不允许的)

----------

知道以上的主要区别之后就可以编写 PR 自动审查了

首先需要获取源仓库的内容 (当然绝对不可以直接 checkout!!!)

可以选择在当前目录来获取修改，或者创建一个新文件夹来获取修改

```yml
# Way 1
- uses: actions/checkout@v2
  with:
    ref: pull/${{ github.event.pull_request.number }}/head
    path: the_pr

# Way 2
- run: git fetch origin pull/$PR_NUM/head:THE_PR
  env:
    PR_NUM: ${{ github.event.pull_request.number }}
```

然后是提取该 PR 的修改

```shell
BASE_SHA: ${{ github.event.pull_request.base.sha }}

git rev-list --count "$BASE_SHA..THE_PR" > tmp/count
cat tmp/count
git --no-pager diff "$BASE_SHA..THE_PR" --no-color --output tmp/change-diff
git --no-pager diff "$BASE_SHA..THE_PR" --name-only --output tmp/name-changed
```

此时
- `tmp/name-changed` 存储着该 PR 修改的全部文件的文件路径
- `tmp/change-diff` 则为 PR 与 base 的 diff 文件
- `tmp/count` 为一个数字, 该数字代表 base 与 pr 直接相差的 commit 数量

----

在进行一系列 PR 审核之后, 需要将审核结果返回出去 (`Merge` 或者 `Reject(Request change)`)

需要用到的两个 REST API 为 [Create a review for a pull request](https://docs.github.com/en/rest/reference/pulls#create-a-review-for-a-pull-request), [Merge a pull request](https://docs.github.com/en/rest/reference/pulls#merge-a-pull-request)

通过 `Create a review for a pull request` 可以对一个 PR 进行自动审查, 可以是 `Approve` 或者 `Reject(Request changes)`, 亦或者只是简单的评论 `Comment`

然后就可以通过 `Merge a pull request` 完成全自动 PR 合并了, 唯一需要给定的参数 `sha` 为 PullRequest 的最后一个 commit 的 id, 可以通过执行 `git rev-parse THE_PR` 获得该参数的值

----

额外话: 使用 `${{ secrets.GITHUB_TOKEN }}` 合并后, 不会触发 workflow `on: push`
如果需要 merge commit 也执行 `on: push` 的, 请使用 `${{ secrets.PR_REVIEWER_TOKEN }}` 代替 `GITHUB_TOKEN`

----

参考与应用

- [auto-review-and-merge.yml](https://github.com/project-mirai/mirai-repo-mirror/blob/master/.github/workflows/auto-review-and-merge.yml)
- [check-pr.js](https://github.com/project-mirai/mirai-repo-mirror/blob/master/.script/check-pr.js)
