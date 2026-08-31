PH = PH or {}
PH.Utils = PH.Utils or {}

--- Log conditionat de Config.Debug
function PH.Log(...)
    if Config and Config.Debug then
        print('^5[ph-core]^7', ...)
    end
end

--- Elimina spatiile de la inceput/sfarsit
function PH.Utils.Trim(s)
    if type(s) ~= 'string' then return '' end
    return (s:gsub('^%s*(.-)%s*$', '%1'))
end

--- true daca string-ul e gol dupa trim
function PH.Utils.Empty(s)
    return PH.Utils.Trim(tostring(s or '')) == ''
end

--- Capitalizeaza prima litera, restul lowercase ("iOn" -> "Ion")
function PH.Utils.TitleCase(s)
    s = PH.Utils.Trim(s):lower()
    return (s:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

--- Varsta in ani intregi dintr-o data "YYYY-MM-DD" fata de acum
function PH.Utils.AgeFromDob(dob)
    local y, m, d = tostring(dob):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)

    local now  = os.date('*t')
    local age  = now.year - y
    if (now.month < m) or (now.month == m and now.day < d) then
        age = age - 1
    end
    return age
end
