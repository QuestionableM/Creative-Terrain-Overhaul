function GenerateTreeList()
	local data = sm.json.open("$SURVIVAL_DATA/Harvestables/Database/HarvestableSets/hvs_trees.json")
	local final_string = "\nlocal hvs_table =\n{\n"
	for k, v in pairs(data.harvestableList) do
		final_string = final_string.."\t{ sm.uuid.new(\""..tostring(v.uuid).."\"), { "

		for i, a in pairs(v.color) do
			if i > 1 then
				final_string = final_string..", "
			end
			final_string = final_string.."0x"..a
		end

		final_string = final_string.." }, "..#v.color.." }, --"..v.name.."\n"
	end
	final_string = final_string.."}"
	print(final_string)
end