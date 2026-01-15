local M = {}

-- Internal cache for provider versions
M._cache = {}
M._cache_ttl = 3600

--- Make an HTTP GET request
--- @param url string The URL to fetch
--- @return string|nil body The response body or nil on error
--- @return string|nil error Error message if request failed
local function http_get(url)
	local ok, plenary_curl = pcall(require, "plenary.curl")
	if ok then
		local response = plenary_curl.get(url, {
			headers = {
				["Accept"] = "application/vnd.api+json",
			},
			timeout = 10000,
		})
		if response.status == 200 then
			return response.body, nil
		else
			return nil, "HTTP error: " .. response.status
		end
	else
		-- Fallback to system curl
		local cmd = string.format(
			'curl -s -H "Accept: application/vnd.api+json" "%s"',
			url
		)
		local result = vim.fn.system(cmd)
		local exit_code = vim.v.shell_error
		if exit_code ~= 0 then
			return nil, "curl failed with exit code: " .. exit_code
		end
		return result, nil
	end
end

--- Parse JSON response
--- @param json_str string JSON string to parse
--- @return table|nil data Parsed data or nil on error
--- @return string|nil error Error message if parsing failed
local function parse_json(json_str)
	local ok, result = pcall(vim.json.decode, json_str)
	if ok then
		return result, nil
	else
		return nil, "JSON parse error: " .. tostring(result)
	end
end

--- Get provider version ID from registry
--- @param namespace string Provider namespace (e.g., "hashicorp")
--- @param name string Provider name (e.g., "aws")
--- @return string|nil version_id The provider version ID
--- @return string|nil error Error message if lookup failed
function M.get_provider_version_id(namespace, name)
	-- Check cache first
	local cache_key = namespace .. "/" .. name
	local cached = M._cache[cache_key]
	if cached and (os.time() - cached.timestamp) < M._cache_ttl then
		return cached.version_id, nil
	end

	local url = string.format(
		"https://registry.terraform.io/v2/providers/%s/%s/provider-versions?page[size]=1",
		namespace,
		name
	)

	local body, err = http_get(url)
	if err then
		return nil, err
	end

	local data, parse_err = parse_json(body)
	if parse_err then
		return nil, parse_err
	end

	-- Get the latest version (first in the list)
	if data.data and #data.data > 0 then
		local version_id = data.data[1].id
		-- Cache the result
		M._cache[cache_key] = {
			version_id = version_id,
			timestamp = os.time(),
		}
		return version_id, nil
	end

	return nil, "No provider versions found"
end

--- Get documentation ID for a specific resource/data source
--- @param version_id string Provider version ID
--- @param doc_type string "resources" or "data-sources"
--- @param resource_name string Resource name (e.g., "vpc")
--- @return string|nil doc_id The documentation ID
--- @return string|nil error Error message if lookup failed
function M.get_doc_id(version_id, doc_type, resource_name)
	local url = string.format(
		"https://registry.terraform.io/v2/provider-versions/%s?include=provider-docs",
		version_id
	)

	local body, err = http_get(url)
	if err then
		return nil, err
	end

	local data, parse_err = parse_json(body)
	if parse_err then
		return nil, parse_err
	end

	-- Map doc_type to category
	local category = doc_type

	-- Find matching doc in included provider-docs
	if data.included then
		for _, doc in ipairs(data.included) do
			if doc.type == "provider-docs" then
				local attrs = doc.attributes
				if attrs.category == category and attrs.slug == resource_name then
					return doc.id, nil
				end
			end
		end
	end

	return nil, string.format("Documentation not found for %s/%s", category, resource_name)
end

--- Fetch the markdown content for a documentation
--- @param doc_id string Documentation ID
--- @return string|nil content The markdown content
--- @return string|nil error Error message if fetch failed
function M.fetch_doc_content(doc_id)
	local url = string.format("https://registry.terraform.io/v2/provider-docs/%s", doc_id)

	local body, err = http_get(url)
	if err then
		return nil, err
	end

	local data, parse_err = parse_json(body)
	if parse_err then
		return nil, parse_err
	end

	if data.data and data.data.attributes and data.data.attributes.content then
		return data.data.attributes.content, nil
	end

	return nil, "No content found in documentation"
end

--- Strip YAML frontmatter from markdown content
--- @param content string Markdown content potentially with frontmatter
--- @return string content Markdown content without frontmatter
function M.strip_frontmatter(content)
	-- Match YAML frontmatter: starts with ---, ends with ---
	local stripped = content:gsub("^%-%-%-%s*\n.-\n%-%-%-%s*\n", "")
	return stripped
end

--- Set cache TTL
--- @param ttl number TTL in seconds
function M.set_cache_ttl(ttl)
	M._cache_ttl = ttl
end

--- Clear the cache
function M.clear_cache()
	M._cache = {}
end

return M
