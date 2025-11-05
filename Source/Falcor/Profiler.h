#pragma once
#include <iostream>
#include <string>
#include <unordered_map>
#include <chrono>

namespace Tools
{
/// <summary>
/// 时间统计工具
/// </summary>
class Profiler
{
public:
    inline static std::unordered_map<std::string, std::chrono::steady_clock::duration> timeDict = {};
    inline static std::unordered_map<std::string, std::chrono::steady_clock::time_point> timerDict = {};

    /// <summary>
    /// 开始统计某任务的时间
    /// </summary>
    /// <param name="taskName">任务名</param>
    static void BeginSample(std::string taskName) { timerDict[taskName] = std::chrono::steady_clock::now(); }

    /// <summary>
    /// 停止统计某任务的时间
    /// </summary>
    /// <param name="taskName">任务名</param>
    static void EndSample(std::string taskName)
    {
        if (timerDict.find(taskName) == timerDict.cend())
            std::cout << taskName << "TIMER NOT START" << std::endl;
        else
            timeDict[taskName] += std::chrono::steady_clock::now() - timerDict[taskName];
    }
    /// <summary>
    /// 将目前统计的时间清零
    /// </summary>
    static void Reset()
    {
        timeDict.clear();
        timerDict.clear();
    }
    /// <summary>
    /// 在控制台输出当前统计的时间
    /// </summary>
    static void Print()
    {
        for (auto& pair : timeDict)
        {
            std::cout << pair.first << " RUNNING TIME:" << std::chrono::duration<double>(pair.second).count() << "s" << std::endl;
        }
        std::cout << std::endl;
    }
};
} // namespace Tools
