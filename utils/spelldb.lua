local spelldb = {}

-- Retry constants for database population
spelldb.MAX_POPULATE_RETRIES = 5
spelldb.MIN_RETRY_DELAY_MS = 100
spelldb.MAX_RETRY_DELAY_MS = 500

-- Attempt to load an SQLite3 library. lsqlite3 is common.
local success, sqlite3 = pcall(require, 'lsqlite3')
if not success then
    -- Log or print an error. For now, we'll print.
    -- In a more integrated system, this would use the project's logger.
    print("ERROR: SQLite3 library (lsqlite3) not found. Spell database functionality will be disabled.")
    -- Return a stub module if SQLite is not available, so require doesn't break
    function spelldb.is_available() return false end
    return spelldb
end

function spelldb.is_available() return true end

-- Configurable constants
spelldb.DB_FILENAME = mq.configDir .. "/aqo_spells.db" -- Assumes mq.configDir is valid
spelldb.TABLE_NAME = "spells"

spelldb.COLUMNS = {
    spell_id          = "INTEGER PRIMARY KEY", -- Using spell_id as primary key
    name              = "TEXT UNIQUE", -- Spell names should be unique
    level             = "INTEGER",
    category          = "TEXT",
    subcategory       = "TEXT",
    description       = "TEXT",
    target_type       = "TEXT",
    cast_time_ms      = "INTEGER",
    duration_ticks    = "INTEGER",
    duration_seconds  = "REAL",
    mana_cost         = "INTEGER",
    skill             = "TEXT",
    resist_type       = "TEXT",
    beneficial        = "INTEGER", -- 0 for false, 1 for true
    ae_range          = "REAL",
    push_back         = "REAL",
    range             = "REAL",
    hate_override     = "INTEGER",
    endurance_cost    = "INTEGER"
}

local db_instance = nil

--- Opens a connection to the SQLite database.
-- @return userdata|nil The database object, or nil on failure.
function spelldb.get_db()
    if not sqlite3 then return nil end
    if db_instance then return db_instance end

    local db = sqlite3.open(spelldb.DB_FILENAME)
    if not db then
        print("ERROR: Could not open spell database: " .. spelldb.DB_FILENAME)
        return nil
    end
    db_instance = db
    return db_instance
end

--- Closes the database connection.
function spelldb.close_db()
    if db_instance then
        db_instance:close()
        db_instance = nil
    end
end

--- Initializes the database and creates the spells table if it doesn't exist.
function spelldb.initialize_database()
    if not sqlite3 then return end

    local db = spelldb.get_db()
    if not db then return end

    local column_definitions = {}
    for col_name, col_type in pairs(spelldb.COLUMNS) do
        table.insert(column_definitions, col_name .. " " .. col_type)
    end

    local create_table_sql = string.format(
        "CREATE TABLE IF NOT EXISTS %s (%s);",
        spelldb.TABLE_NAME,
        table.concat(column_definitions, ", ")
    )

    local result = db:exec(create_table_sql)
    if result ~= sqlite3.OK then
        print("ERROR: Failed to create spells table: " .. db:errmsg())
        -- spelldb.close_db() -- Close DB if table creation fails
        return false
    end

    -- print("Spell database initialized successfully. Table '" .. spelldb.TABLE_NAME .. "' is ready.")
    -- Keep DB open for subsequent operations in this session if needed, or close it.
    -- For now, let's keep it open as get_db() manages a singleton instance.
    return true
end

--- Populates the spell database by iterating through spells.
function spelldb.populate_spell_database(max_spell_id)
    if not sqlite3 then
        print("ERROR: SQLite not available, cannot populate spell database.")
        return false
    end

    local db = spelldb.get_db()
    if not db then return false end

    max_spell_id = max_spell_id or 50000 -- Default to checking up to spell ID 50000

    local attempts = 0
    local transaction_successful = false
    local total_spells_processed_across_retries = 0
    local total_spells_added_across_retries = 0
    local total_spells_errored_across_retries = 0

    while attempts < spelldb.MAX_POPULATE_RETRIES and not transaction_successful do
        attempts = attempts + 1
        local current_attempt_spells_processed = 0
        local current_attempt_spells_added = 0
        local current_attempt_spells_errored = 0
        local spell_processing_error_occured_this_attempt = false

        -- Try to get a write lock earlier.
        local begin_result = db:exec("BEGIN IMMEDIATE TRANSACTION;")
        if begin_result ~= sqlite3.OK then
            local errcode = db:errcode()
            if (errcode == sqlite3.BUSY or errcode == sqlite3.LOCKED) and attempts < spelldb.MAX_POPULATE_RETRIES then
                local delay_ms = math.random(spelldb.MIN_RETRY_DELAY_MS, spelldb.MAX_RETRY_DELAY_MS)
                print(string.format("Spell DB Population: BEGIN IMMEDIATE failed (attempt %d/%d) due to lock/busy. Retrying in %d ms. Error: %s",
                                    attempts, spelldb.MAX_POPULATE_RETRIES, delay_ms, db:errmsg()))
                if mq and mq.delay then mq.delay(delay_ms) else print("mq.delay not available for retry delay") end
                goto continue_transaction_attempt -- Skips to the next iteration of the while loop
            else
                print(string.format("ERROR: Failed to begin transaction after %d attempts: %s (Code: %d)", attempts, db:errmsg(), errcode))
                return false -- Non-retryable error or max retries hit for BEGIN
            end
        end

        print(string.format("Spell DB Population: Began transaction (attempt %d/%d). Processing spells up to ID %d...", attempts, spelldb.MAX_POPULATE_RETRIES, max_spell_id))

        local insert_sql_template = nil
        -- Note: spells_processed, spells_added, spells_errored are now per-attempt

        for id = 1, max_spell_id do
            local spell_tlo = mq.TLO.Spell(id)

            if spell_tlo.IsValid() then
                local level = spell_tlo.Level()
                if level == 255 or (level >= 1 and level <= 200) then -- Class spells (1-200) or AA/Disc spells (255)
                    local spell_data = {}
                    spell_data.spell_id = id
                    spell_data.name = spell_tlo.Name()
                    spell_data.level = level
                    spell_data.category = spell_tlo.Category()
                    spell_data.subcategory = spell_tlo.SubCategory()
                    spell_data.description = spell_tlo.Desc()
                    spell_data.target_type = spell_tlo.TargetType()
                    spell_data.cast_time_ms = spell_tlo.MyCastTime()
                    spell_data.duration_ticks = spell_tlo.Duration()
                    spell_data.duration_seconds = spell_tlo.Duration.TotalSeconds()
                    spell_data.mana_cost = spell_tlo.Mana()
                    spell_data.skill = spell_tlo.Skill()
                    spell_data.resist_type = spell_tlo.ResistType()
                    spell_data.beneficial = spell_tlo.Beneficial() and 1 or 0
                    spell_data.ae_range = spell_tlo.AERange()
                    spell_data.push_back = spell_tlo.PushBack()
                    spell_data.range = spell_tlo.MyRange()
                    spell_data.hate_override = spell_tlo.HateOverride()
                    spell_data.endurance_cost = spell_tlo.EnduranceCost()

                    if not spell_data.name then
                        goto continue_spell_loop
                    end

                    if not insert_sql_template then
                        local columns = {}
                        local placeholders = {}
                        for col_name, _ in pairs(spelldb.COLUMNS) do
                            table.insert(columns, col_name)
                            table.insert(placeholders, ":" .. col_name)
                        end
                        insert_sql_template = string.format(
                            "INSERT OR IGNORE INTO %s (%s) VALUES (%s);",
                            spelldb.TABLE_NAME,
                            table.concat(columns, ", "),
                            table.concat(placeholders, ", ")
                        )
                    end

                    local stmt, err = db:prepare(insert_sql_template)
                    if not stmt then
                        print(string.format("ERROR: Failed to prepare insert statement for spell ID %d: %s", id, err or db:errmsg()))
                        current_attempt_spells_errored = current_attempt_spells_errored + 1
                        -- This is a non-DB lock error, probably indicates a bigger issue with the SQL or DB state.
                        -- Could set spell_processing_error_occured_this_attempt = true here if we want to abort the transaction.
                        goto continue_spell_loop
                    end

                    local bind_params = {}
                    for col_name, _ in pairs(spelldb.COLUMNS) do
                        bind_params[":" .. col_name] = spell_data[col_name]
                    end

                    local all_params_bound = true
                    for col_name_placeholder, value_to_bind in pairs(bind_params) do
                        -- col_name_placeholder is like ":spell_id", value_to_bind is the actual data
                        local bind_ok, err_msg_bind = stmt:bind(col_name_placeholder, value_to_bind)
                        if not bind_ok then
                            print(string.format("ERROR: Failed to bind parameter %s for spell ID %d (%s): %s",
                                                col_name_placeholder, spell_data.spell_id, spell_data.name or "N/A", err_msg_bind or stmt:errmsg()))
                            current_attempt_spells_errored = current_attempt_spells_errored + 1
                            all_params_bound = false
                            break -- Stop binding for this spell if one fails
                        end
                    end

                    if not all_params_bound then
                        stmt:finalize()
                        goto continue_spell_loop -- Skip to the next spell ID
                    end

                    local exec_result, exec_err = stmt:step()
                    if exec_result ~= sqlite3.DONE then
                        local current_errmsg = db:errmsg()
                        local errcode_step = db:errcode() -- Get error code for step
                        if (errcode_step == sqlite3.BUSY or errcode_step == sqlite3.LOCKED) then
                             print(string.format("WARNING: INSERT for spell ID %d (%s) failed due to BUSY/LOCKED: %s. This transaction will likely be retried.", id, spell_data.name or "N/A", exec_err or current_errmsg))
                             -- This might be a case to set spell_processing_error_occured_this_attempt = true and break,
                             -- forcing a transaction retry. For now, we just log and count as error for this spell.
                             current_attempt_spells_errored = current_attempt_spells_errored + 1
                             -- spell_processing_error_occured_this_attempt = true -- Optional: force transaction retry
                             -- stmt:finalize()
                             -- break -- from spell loop
                        elseif current_errmsg and current_errmsg ~= "not an error" and current_errmsg:lower():find("constraint failed") == nil then
                            print(string.format("ERROR: Failed to insert spell ID %d (%s): %s (Result: %s)", id, spell_data.name or "N/A", exec_err or current_errmsg, exec_result))
                            current_attempt_spells_errored = current_attempt_spells_errored + 1
                        end
                    else
                        if db:changes() > 0 then
                            current_attempt_spells_added = current_attempt_spells_added + 1
                        end
                    end
                    stmt:finalize()
                    current_attempt_spells_processed = current_attempt_spells_processed + 1
                end
            end
            ::continue_spell_loop::
        end -- end for id loop

        if spell_processing_error_occured_this_attempt then
            db:exec("ROLLBACK;")
            print(string.format("Spell DB Population: Transaction (attempt %d/%d) rolled back due to spell processing errors.", attempts, spelldb.MAX_POPULATE_RETRIES))
            if attempts < spelldb.MAX_POPULATE_RETRIES then
                local delay_ms = math.random(spelldb.MIN_RETRY_DELAY_MS, spelldb.MAX_RETRY_DELAY_MS)
                print(string.format("Retrying in %d ms.", delay_ms))
                if mq and mq.delay then mq.delay(delay_ms) else print("mq.delay not available for retry delay") end
            end
            goto continue_transaction_attempt
        end

        local commit_result = db:exec("COMMIT;")
        if commit_result == sqlite3.OK then
            transaction_successful = true
            total_spells_processed_across_retries = total_spells_processed_across_retries + current_attempt_spells_processed
            total_spells_added_across_retries = total_spells_added_across_retries + current_attempt_spells_added
            total_spells_errored_across_retries = total_spells_errored_across_retries + current_attempt_spells_errored
            print(string.format("Spell DB Population: Transaction committed successfully on attempt %d.", attempts))
            print(string.format("Attempt %d summary: Processed: %d, Added: %d, Errored: %d", attempts, current_attempt_spells_processed, current_attempt_spells_added, current_attempt_spells_errored))
        else
            local errcode = db:errcode()
            db:exec("ROLLBACK;") -- Rollback on any commit failure
            if (errcode == sqlite3.BUSY or errcode == sqlite3.LOCKED) and attempts < spelldb.MAX_POPULATE_RETRIES then
                local delay_ms = math.random(spelldb.MIN_RETRY_DELAY_MS, spelldb.MAX_RETRY_DELAY_MS)
                print(string.format("Spell DB Population: COMMIT failed (attempt %d/%d) due to lock/busy. Retrying in %d ms. Error: %s",
                                    attempts, spelldb.MAX_POPULATE_RETRIES, delay_ms, db:errmsg()))
                if mq and mq.delay then mq.delay(delay_ms) else print("mq.delay not available for retry delay") end
            else
                print(string.format("ERROR: Failed to commit transaction after %d attempts: %s (Code: %d)", attempts, db:errmsg(), errcode))
                return false
            end
        end
        ::continue_transaction_attempt::
    end -- while attempts

    if not transaction_successful then
        print("ERROR: Spell DB Population failed after max retries.")
        return false
    end

    print(string.format("Spell database population complete. Total Processed: %d, Total Added/Updated: %d, Total Errored over final successful attempt: %d", total_spells_processed_across_retries, total_spells_added_across_retries, total_spells_errored_across_retries))
    return true
end

-- Add a way to close the DB when the script exits, if necessary.
-- This might be handled by the main script's shutdown sequence.
-- For now, we can add an explicit call or rely on script termination.

--- Fetches spells from the database based on flexible criteria.
-- @param criteria table A table containing query, params, orderby, and limit.
--   - Query (string): The WHERE clause (e.g., "category = :category AND level >= :min_level").
--   - Params (table): Parameters for the WHERE clause (e.g., { [":category"] = "Heal", [":min_level"] = 60 }).
--   - OrderBy (string): ORDER BY clause (e.g., "level DESC, name ASC"). Defaults to "level DESC".
--   - Limit (integer): LIMIT clause. Defaults to 1.
-- @return table|nil A list of spell data tables, or nil on error.
function spelldb.get_spells_by_criteria(criteria)
    if not sqlite3 then
        print("ERROR: SQLite not available, cannot query spell database.")
        return nil
    end

    local db = spelldb.get_db()
    if not db then return nil end

    criteria = criteria or {}
    local query_parts = {"SELECT * FROM " .. spelldb.TABLE_NAME}

    if criteria.Query and type(criteria.Query) == "string" and #criteria.Query > 0 then
        table.insert(query_parts, "WHERE " .. criteria.Query)
    end

    table.insert(query_parts, "ORDER BY " .. (criteria.OrderBy or "level DESC"))
    table.insert(query_parts, "LIMIT " .. (criteria.Limit or 1))

    local sql_query = table.concat(query_parts, " ")
    -- print("Executing spell query: " .. sql_query) -- For debugging

    local stmt, err = db:prepare(sql_query)
    if not stmt then
        print(string.format("ERROR: Failed to prepare spell query statement [%s]: %s", sql_query, err or db:errmsg()))
        return nil
    end

    if criteria.Params and type(criteria.Params) == "table" then
        local bind_result, bind_err = stmt:bind_values(criteria.Params)
        if not bind_result then
            print(string.format("ERROR: Failed to bind parameters for spell query [%s]: %s", sql_query, bind_err or stmt:errmsg()))
            stmt:finalize()
            return nil
        end
    end

    local spells_found = {}
    while true do
        local result_code, err_msg = stmt:step()
        if result_code == sqlite3.ROW then
            local row_data = stmt:get_named_values()
            -- Convert beneficial back to boolean if needed by abilities.Spell:new, though it's stored as INT
            -- For now, keep as is, and abilities.Spell:new can handle it or be adapted.
            table.insert(spells_found, row_data)
        elseif result_code == sqlite3.DONE then
            break
        else
            print(string.format("ERROR: Spell query execution error [%s]: %s (Code: %s)", sql_query, err_msg or stmt:errmsg(), result_code))
            stmt:finalize()
            return nil -- Or empty list
        end
    end
    stmt:finalize()

    -- print(string.format("Query returned %d spells.", #spells_found)) -- For debugging
    return spells_found
end

return spelldb
