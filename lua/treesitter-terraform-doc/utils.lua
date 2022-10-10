local M = {}

---
--- Merge 2 table reccursivly
--- found at: https://gist.github.com/revolucas/184aec7998a6be5d2f61b984fac1d7f7
---
---@param into table The result table.
---@param from table The input table.
---@return     table The result table populated.
M.table_merge = function(into, from)
    local stack = {}
    local node1 = into
    local node2 = from

    while (true) do
        for k, v in pairs(node2) do
            if (type(v) == "table" and type(node1[k]) == "table") then
                table.insert(stack, { node1[k], node2[k] })
            else
                node1[k] = v
            end
        end
        if (#stack > 0) then
            local t = stack[#stack]
            node1, node2 = t[1], t[2]
            stack[#stack] = nil
        else
            break
        end
    end
    return into
end

return M
