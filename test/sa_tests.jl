import AMG: scale_cols_by_largest_entry!, strength_of_connection, 
            SymmetricStrength, poisson
function symmetric_soc(A::SparseMatrixCSC{T,V}, θ) where {T,V}
    D = abs.(diag(A))
    i,j,v = findnz(A)
    mask = i .!= j
    DD = D[i] .* D[j] 
    mask = mask .& (abs.(v.^2) .>= (θ * θ * DD))

    i = i[mask]
    j = j[mask]
    v = v[mask]

    S = sparse(i,j,v, size(A)...) + spdiagm(D)

    scale_cols_by_largest_entry!(S)

    for i = 1:size(S.nzval,1)
        S.nzval[i] = abs(S.nzval[i])
    end

    S
end

# Set up tests
function test_symmetric_soc()

    cases = generate_matrices()

    for matrix in cases
        for θ in (0.0, 0.1, 0.5, 1., 10.)
            ref_matrix = symmetric_soc(matrix, θ)
            calc_matrix = strength_of_connection(SymmetricStrength(θ), matrix)

            @test sum(abs2, ref_matrix - calc_matrix) < 1e-6
        end
    end
end

function generate_matrices()
    
    cases = []

    # Random matrices
    srand(0)
    for T in (Float32, Float64)
        
        for s in [2, 3, 5]
            push!(cases, sprand(T, s, s, 1.))
        end

        for s in [2, 3, 5, 7, 10, 11, 19]
            push!(cases, poisson(T, s))
        end
    end

    cases
end

function stand_agg(C)
    n = size(C, 1)

    R = Set(1:n)
    j = 0
    Cpts = Int[]

    aggregates = -ones(Int, n)

    # Pass 1
    for i = 1:n
        Ni = union!(Set(C.rowval[nzrange(C, i)]), Set(i))
        if issubset(Ni, R)
            push!(Cpts, i)
            setdiff!(R, Ni)
            for x in Ni
                aggregates[x] = j
            end
            j += 1
        end
    end

    # Pass 2
    old_R = copy(R)
    for i = 1:n
        if ! (i in R)
            continue
        end

        for x in C.rowval[nzrange(C, i)]
            if !(x in old_R)
                aggregates[i] = aggregates[x]
                setdiff!(R, i)
                break
            end
        end
    end

    # Pass 3
    for i = 1:n
        if !(i in R)
            continue
        end
        Ni = union(Set(C.rowval[nzrange(C,i)]), Set(i))
        push!(Cpts, i)

        for x in Ni
            if x in R
                aggregates[x] = j
            end
            j += 1
        end
    end

    @assert length(R) == 0

    Pj = aggregates + 1
    Pp = collect(1:n+1)
    Px = ones(eltype(C), n)

    SparseMatrixCSC(maximum(aggregates + 1), n, Pp, Pj, Px)
end

# Standard aggregation tests
function test_standard_aggregation()

    cases = generate_matrices()

    for matrix in cases
        for θ in (0.0, 0.1, 0.5, 1., 10.)
            C = symmetric_soc(matrix, θ)
            calc_matrix = aggregation(StandardAggregation(), matrix)
            ref_matrix = stand_agg(matrix)
            @test sum(abs2, ref_matrix - calc_matrix) < 1e-6
        end
    end

end

# Test fit_candidates 
function test_fit_candidates()

    cases = generate_fit_candidates_cases()

    for (i, (AggOp, fine_candidates)) in enumerate(cases)
   
        mask_candidates!(AggOp, fine_candidates)

        Q, coarse_candidates = fit_candidates(AggOp, fine_candidates)

        @test isapprox(fine_candidates, Q * coarse_candidates)
        @test isapprox(Q * (Q' * fine_candidates), fine_candidates)
    end
end
function mask_candidates!(A,B)
    B[(diff(A.colptr) .== 0)] = 0
end

function generate_fit_candidates_cases()
    cases = []

    for T in (Float32, Float64)

        # One candidate
        AggOp = SparseMatrixCSC(2, 5, collect(1:6), 
                        [1,1,1,2,2], ones(T,5))
        B =  ones(T,5)
        push!(cases, (AggOp, B))

        AggOp = SparseMatrixCSC(2, 5, collect(1:6), 
                        [2,2,1,1,1], ones(T,5))
        B = ones(T, 5)
        push!(cases, (AggOp, B))

        AggOp = SparseMatrixCSC(3, 9, collect(1:10), 
                        [1,1,1,2,2,2,3,3,3], ones(T, 9))
        B = ones(T, 9)
        push!(cases, (AggOp, B))

        #AggOp = SparseMatrixCSC(3, 9, collect(1:10), 
                        #[3,2,1,1,2,3,2,1,3], ones(T,9))
        #B = T.(collect(1:9))
        #push!(cases, (AggOp, B))
    end

    cases
end

# Test approximate spectral radius
function test_approximate_spectral_radius()

    cases = []
    srand(0)

    push!(cases, [2. 0.
                  0. 1.])

    push!(cases, [-2. 0.
                   0  1])

    push!(cases, [100.   0.  0.
                    0. 101.  0.
                    0.   0. 99.])

    for i in 2:5
        push!(cases, rand(i,i))
    end

    for A in cases
        E,V = eig(A)
        E = abs.(E)
        largest_eig = find(E .== maximum(E))[1]
        expected_eig = E[largest_eig]

        @test isapprox(approximate_spectral_radius(A), expected_eig)

    end

    # Symmetric matrices
    for A in cases
        A = A + A'
        E,V = eig(A)
        E = abs.(E)
        largest_eig = find(E .== maximum(E))[1]
        expected_eig = E[largest_eig]

        @test isapprox(approximate_spectral_radius(A), expected_eig)

    end

end