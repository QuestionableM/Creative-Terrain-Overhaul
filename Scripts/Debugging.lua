function GenerateTreeList(var_name)
	local data = sm.json.open("$SURVIVAL_DATA/Harvestables/Database/HarvestableSets/hvs_stones.json")
	local final_string = "\nlocal "..var_name.." =\n{\n"
	for k, v in pairs(data.harvestableList) do
		final_string = final_string.."\t{ sm.uuid.new(\""..tostring(v.uuid).."\"), { "

		local table_sz
		if type(v.color) == "table" then
			table_sz = #v.color

			for i, a in pairs(v.color) do
				if i > 1 then
					final_string = final_string..", "
				end
				final_string = final_string.."0x"..a
			end
		else
			table_sz = 1
			final_string = final_string.."0x"..v.color
		end

		final_string = final_string.." }, "..table_sz.." }, --"..v.name.."\n"
	end
	final_string = final_string.."}"
	print(final_string)
end