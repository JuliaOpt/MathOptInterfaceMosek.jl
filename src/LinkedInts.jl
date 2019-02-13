using Printf                    #

mutable struct LinkedInts
    next :: Vector{Int}
    prev :: Vector{Int}

    free_ptr :: Int
    free_cap :: Int
    root     :: Int

    block :: Vector{Int}
    size  :: Vector{Int}
end

LinkedInts(capacity=128) =
    LinkedInts(Int[],Int[],
               0,0,0,
               Int[],
               Int[])

allocatedlist(s::LinkedInts) = findall(s.block .> 0)
allocated(s::LinkedInts, id :: Int) = id > 0 && id <= length(s.block) && s.block[id] > 0
blocksize(s::LinkedInts, id :: Int) = s.size[id]
Base.length(s::LinkedInts) = length(s.next)
numblocks(s::LinkedInts) = length(s.block)

function Base.show(f::IO, s::LinkedInts)
    print(f,"LinkedInts(\n")
    @printf(f,"  Number of blocks: %d\n", length(s.block))
    @printf(f,"  Number of elements: %d\n", length(s.next))
    print(f,"  Blocks:\n")
    for i in 1:length(s.block)
        if s.block[i] > 0
            idxs = getindexes(s,i)
            print(f,"    #$i: $idxs\n")
        end
    end
    p = s.free_ptr
    freelst = Int[]
    while p > 0
        push!(freelst,p)
        p = s.prev[p]
    end
    print(f,"  Free: $freelst\n")

    println(f,"  free_ptr = $(s.free_ptr)")
    println(f,"  root     = $(s.root)")
    println(f,"  next     = $(s.next)")
    println(f,"  prev     = $(s.prev)")

    print(f,")")
end

"""
    ensurefree(s::LinkedInts, N :: Int)

Ensure that there are at least `N` elements free, and allocate as necessary.
"""
function ensurefree(s::LinkedInts, N :: Int)
    if s.free_cap < N
        num = N - s.free_cap

        cap = length(s.next)
        first = cap+1
        last  = cap+num

        append!(s.next, Int[i+1 for i in first:last])
        append!(s.prev, Int[i-1 for i in first:last])

        s.next[last] = 0
        s.prev[first] = s.free_ptr
        if s.prev[first] > 0
            s.next[s.prev[first]] = first
        end
        s.free_ptr = last
        s.free_cap += num

        return num
    else
        return 0
    end
end

"""
    newblock(s::LinkedInts, N :: Int)

Add a new block in list `idx`
"""
function newblock(s::LinkedInts, N :: Int) :: Int
    @assert(N > 0)
    ensurefree(s, N)
    # remove from free list
    ptre = s.free_ptr
    ptrb = ptre
    for i = 1:N-1
        ptrb = s.prev[ptrb]
    end

    prev = s.prev[ptrb]

    if prev > 0
        s.next[prev] = 0
    end

    s.free_ptr = s.prev[ptrb]
    s.free_cap -= N

    # insert into list `idx`
    s.prev[ptrb] = s.root
    if s.root > 0
        s.next[s.root] = ptrb
    end
    s.root = ptre
    push!(s.block, ptrb)
    push!(s.size, N)

    id = length(s.block)

    #if ! checkconsistency(s)
    #    println("List = ",s)
    #    assert(false)
    #end

    return id
end

"""
Move a block to the free list.
"""
function deleteblock(s::LinkedInts, id :: Int)
    if s.size[id] > 0
        ptrb = s.block[id]
        N = s.size[id]
        ptre = ptrb
        for i in 2:N
            ptre = s.next[ptre]
        end
        prev = s.prev[ptrb]
        next = s.next[ptre]

        # remove from list and clear the block id
        if s.root == ptre s.root = prev end
        if prev > 0 s.next[prev] = next end
        if next > 0 s.prev[next] = prev end

        s.size[id]  = 0
        s.block[id] = 0

        # add to free list
        if s.free_ptr > 0
            s.next[s.free_ptr] = ptrb
        end
        s.prev[ptrb] = s.free_ptr
        s.free_ptr = ptre
        s.next[ptre] = 0

        s.free_cap += N
    end
end

"""
    getindex(s::LinkedInts, id::Int)

Shortcut for `getindexes(s, id)[1]` when `s.size[id]` is 1.
"""
function getindex(s::LinkedInts, id::Int)
    @assert s.size[id] == 1
    return s.block[id]
end

"""
    getindexes(s::LinkedInts, id :: Int)

Return the vector of indices for the block `id`.
"""
function getindexes(s::LinkedInts, id :: Int)
    N = s.size[id]
    r = Vector{Int}(undef, N)
    p = s.block[id]
    for i in 1:N
        r[i] = p
        p = s.next[p]
    end
    return r
end

function getindexes(s::LinkedInts, id::Int, target::Vector{Int}, offset::Int)
    N = s.size[id]
    p = s.block[id]
    for i in 1:N
        target[i+offset-1] = p
        p = s.next[p]
    end
    return N
end

function getindexes(s::LinkedInts, ids::Vector{Int})
    N = sum(map(id -> s.size[id], ids))
    r = Vector{Int}(undef,N)
    offset = 1
    for id in ids
        offset += getindexes(s, id, r, offset)
    end
    return r
end

function getoneindex(s::LinkedInts, id :: Int)
    N = s.size[id]
    if N < 1
        error("No values at id")
    end

    s.block[i]
end


"""
Get a list if the currently free elements.
"""
function getfreeindexes(s::LinkedInts)
    N = s.free_cap
    r = Array{Int}(undef,N)
    ptr = s.free_ptr
    for i in 1:N
        r[N-i+1] = ptr
        ptr  = s.prev[ptr]
    end
    r
end



"""
Get a list if the currently used elements.
"""
function getusedindexes(s::LinkedInts)
    N = length(s.next) - s.free_cap
    r = Array{Int}(undef,N)
    ptr = s.root
    for i in 1:N
        r[N-i+1] = ptr
        ptr  = s.prev[ptr]
    end
    r
end



"""
Check consistency of the internal structures.
"""
function checkconsistency(s::LinkedInts) :: Bool
    if length(s.prev) != length(s.next)
        return false
    end

    N = length(s.prev)


    if ! (all(i -> s.prev[i] == 0 || s.next[s.prev[i]] == i, 1:N) &&
          all(i -> s.next[i] == 0 || s.prev[s.next[i]] == i, 1:N))
        @assert(false)
    end

    mark = fill(false,length(s.prev))

    p = s.free_ptr
    while p != 0
        mark[p] = true
        p = s.prev[p]
    end

    p = s.root
    while p != 0
        @assert(!mark[p])
        mark[p] = true
        p = s.prev[p]
    end

    if !all(mark)
        println(s)
        println(mark)
        @assert(all(mark))
    end

    return true
end
