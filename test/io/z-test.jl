# io/z-test.jl

using Test: @testset

list = [
"caller_name.jl"
"fld-read.jl"
"fld-write.jl"
"ir_dump.jl"
"prompt.jl"
"shows.jl"
]

for file in list
	@testset "$file" begin
		include(file)
	end
end
