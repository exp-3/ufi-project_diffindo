print("ufiStudio ZXIC MTD打包工具")
print("版权所有 (C) 2024 ufiTech Developers. 保留所有权利。")
print("=====================================")

local json = require("__lib__.json")
local file_path
-- 获取输入文件路径
local args = {...}
if #args > 0 then
    file_path = args[1]
    if string.sub(file_path, -1) ~= "/" then
        file_path = file_path .. "/"
    end
else
    file_path = "MTDs/"
end
-- 检测工程文件夹是否存在
local f1 = io.open(file_path .. "/partitions.json", "r")
if f1 then
    pcall(function()
        f1:close()
    end)
else
    print("无法识别工程文件夹，请检查：", file_path)
    os.exit()
end

local log = function(msg)
    -- 初始化日志函数
end
local log_path = "__lib__/logs/"
local els = io.open("__lib__/--enable-log", "r")
if els then -- 检测是否存在--enable-log文件
    els:close()
    print("\r\n日志输出已启用。\r\n")
    os.execute("mkdir -p " .. log_path) -- 创建日志文件夹
    local log_file = string.format("%s%s_repk.log", log_path, os.time())
    log = function(msg)
        local f = io.open(log_file, "a")
        f:write(msg .. "\r\n")
        f:close()
    end
end

log(os.date("%Y-%m-%d %H:%M:%S") .. "\t开始...\r\n")

local printr = print
local function echo(msg)
    log("\r\n" .. msg .. "\r\n")
    printr(msg)
end
local print = echo

local function exec(cmd)
    local f = io.popen(cmd)
    local s = f:read("*a")
    f:close()
    return s
end

local fill = require("__lib__.fillend")

local function repack(mtd, type, erase, size)
    -- 删除可能存在的旧文件
    os.remove(mtd .. "_new")
    -- 打包
    log("=====================================")
    if type == "squashfs" then -- squashfs
        local cmd, comp, block
        cmd = string.format("unsquashfs -s \"%s\" | grep Compression", mtd)
        comp = exec(cmd)
        log(comp) -- 测试输出
        comp = comp:match("Compression (%w+)") or "xz"
        cmd = string.format("unsquashfs -s \"%s\" | grep Block", mtd)
        block = exec(cmd)
        log(block) -- 测试输出
        block = block:match("Block size (%d+)") or "262144"
        log("压缩方式：" .. comp .. "，块大小：" .. block)
        cmd = string.format(
            "mksquashfs \"%s\" \"%s\" -comp %s -noappend -b %s -no-xattrs -always-use-fragments -all-root",
            mtd .. "_unpacked", mtd .. "_new", comp, block)
        log(exec(cmd .. " 2>&1"))
        print("已打包squashfs分区：" .. mtd)
    elseif type == "jffs2" then -- jffs2
        local cmd = string.format("mkfs.jffs2 -d \"%s\" -o \"%s\" -X lzo --pagesize=0x800 --eraseblock=%s -l -n -q -v",
            mtd .. "_unpacked", mtd .. "_new", erase)
        log(exec(cmd .. " 2>nul"))
        print("已打包jffs2分区：" .. mtd)
    else -- 其他
        print("已跳过" .. type .. "分区：" .. mtd)
    end
    -- 检查大小并填充
    local f = io.open(mtd .. "_new", "rb")
    if f then
        local new_size = f:seek("end")
        f:close()
        log("打包后大小：" .. new_size .. "，分区大小：" .. size)
        if new_size > size then
            print("错误：打包后文件大小超出分区大小！")
            print("分区最大尺寸：" .. size .. "，打包后大小：" .. new_size)
            print("请重新调整需要打包的文件，减小体积以避免尺寸过大")
            os.remove(mtd .. "_new")
            os.exit()
        end
        if new_size < size then
            log("填充字节：" .. (size - new_size))
            fill(mtd .. "_new", size)
        end
    end
end

printr("开始打包...")

-- 读取分区表
local partition_data = {}
local jf = io.open(file_path .. "partitions.json", "r")
if jf then
    local json_str = jf:read("*a")
    partition_data = json.decode(json_str)
    jf:close()
end

-- 遍历分区表，打包各分区
for i, partition in ipairs(partition_data) do
    -- 找到对应文件
    local target_file = file_path .. partition.file
    -- 检测文件夹是否存在
    local f = exec("ls -d \"" .. target_file:gsub("\\", "/") .. "_unpacked\" 2>/dev/null")
    f = f:match("(.+)%s*$")
    if f then
        repack(target_file, partition.fst, partition.ebs, partition.size)
    else
        log("=====================================")
        print("已跳过分区：" .. target_file .. "，未找到解包文件夹")
    end
end

print("=====================================")
print("打包完成")
log(os.date("%Y-%m-%d %H:%M:%S") .. "\t结束。\r\n")
print(" ")
