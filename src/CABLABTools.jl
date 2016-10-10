module CABLABTools
export mypermutedims!, totuple, freshworkermodule, passobj, @everywhereelsem, toRange, getiperm
# SOme global function definitions

function getiperm(perm)
    iperm = Array(Int,length(perm))
    for i = 1:length(perm)
        iperm[perm[i]] = i
    end
    return ntuple(i->iperm[i],length(iperm))
end

using Base.Cartesian
@generated function mypermutedims!{Q,T,S,N}(dest::AbstractArray{T,N},src::AbstractArray{S,N},perm::Type{Q})
    ind1=ntuple(i->Symbol("i_",i),N)
    ind2=ntuple(i->Symbol("i_",perm.parameters[1].parameters[1][i]),N)
    ex1=Expr(:ref,:src,ind1...)
    ex2=Expr(:ref,:dest,ind2...)
    quote
        @nloops $N i src begin
            $ex2=$ex1
        end
    end
end

totuple(x::AbstractArray)=ntuple(i->x[i],length(x))

@generated function Base.getindex{N}(t::NTuple{N},p::NTuple{N,Int})
    :(@ntuple $N d->t[p[d]])
end

toRange(r::CartesianRange)=map(colon,r.start.I,r.stop.I)
toRange(c1::CartesianIndex,c2::CartesianIndex)=map(colon,c1.I,c2.I)

function passobj(src::Int, target::Vector{Int}, nm::Symbol;
                 from_mod=Main, to_mod=Main)
    r = RemoteChannel(src)
    @spawnat(src, put!(r, getfield(from_mod, nm)))
    @sync for to in target
        @spawnat(to, eval(to_mod, Expr(:(=), nm, fetch(r))))
    end
    nothing
end


function passobj(src::Int, target::Int, nm::Symbol; from_mod=Main, to_mod=Main)
    passobj(src, [target], nm; from_mod=from_mod, to_mod=to_mod)
end


function passobj(src::Int, target, nms::Vector{Symbol};
                 from_mod=Main, to_mod=Main)
    for nm in nms
        passobj(src, target, nm; from_mod=from_mod, to_mod=to_mod)
    end
end

function sendto(p::Int; args...)
    for (nm, val) in args
        @spawnat(p, eval(Main, Expr(:(=), nm, val)))
    end
end


function sendto(ps::Vector{Int}; args...)
    for p in ps
        sendto(p; args...)
    end
end

getfrom(p::Int, nm::Symbol; mod=Main) = fetch(@spawnat(p, getfield(mod, nm)))


function freshworkermodule()
    in(:PMDATMODULE,names(Main)) || eval(Main,:(module PMDATMODULE
        using CABLAB
    end))
    eval(Main,quote
      rs=Future[]
      for pid in workers()
        n=remotecall_fetch(()->in(:PMDATMODULE,names(Main)),pid)
        if !n
          r1=remotecall(()->(eval(Main,:(using CABLAB));nothing),pid)
          r2=remotecall(()->(eval(Main,:(module PMDATMODULE
          using CABLAB
          import CABLAB.Cubes.TempCubes.openTempCube
          import CABLAB.CubeAPI.CachedArrays.CachedArray
          import CABLAB.CubeAPI.CachedArrays.MaskedCacheBlock
          import CABLAB.CubeAPI.CachedArrays
          import CABLAB.CABLABTools.totuple
        end));nothing),pid)
          push!(rs,r1)
          push!(rs,r2)
        end
      end
      [wait(r) for r in rs]
  end)

  nothing
end


macro everywhereelsem(ex)
    quote
        if nprocs()>1
        Base.sync_begin()
        thunk = ()->(eval(Main.PMDATMODULE,$(Expr(:quote,ex))); nothing)
        for pid in workers()
            Base.async_run_thunk(()->remotecall_fetch(thunk,pid))
            yield() # ensure that the remotecall_fetch has been started
        end

        Base.sync_end()
        end
    end
end
end