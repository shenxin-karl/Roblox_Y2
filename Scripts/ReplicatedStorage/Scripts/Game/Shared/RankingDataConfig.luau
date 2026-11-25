-- 协议以这里的顺序传递榜单编号；每月按服务端成绩从高到低排名。
return {
    {
        Name = "IncomeRate",
        ResetType = "Monthly",
        Ascending = false,
        MaxCount = 100,
        DefaultValue = 0,
        UseHistoricalHighScore = true,
        ScoreScale = 100,
    },
    {
        Name = "Playtime",
        ResetType = "Monthly",
        Ascending = false,
        MaxCount = 100,
        DefaultValue = 0,
        UseHistoricalHighScore = true,
        ScoreScale = 1,
    },
}
