using ModelingToolkit, Test
using ModelingToolkit: get_gui_metadata,
    get_ps, getdefault, getname, scalarize,
    VariableDescription, RegularConnector
using URIs: URI
using Distributions
using Unitful

ENV["MTK_ICONS_DIR"] = "$(@__DIR__)/icons"

@connector RealInput begin
    u(t), [input = true, unit = u"V"]
end
@connector RealOutput begin
    u(t), [output = true, unit = u"V"]
end
@mtkmodel Constant begin
    @components begin
        output = RealOutput()
    end
    @parameters begin
        k, [description = "Constant output value of block"]
    end
    @equations begin
        output.u ~ k
    end
end

@variables t [unit = u"s"]
D = Differential(t)

@connector Pin begin
    v(t), [unit = u"V"]                    # Potential at the pin [V]
    i(t), [connect = Flow, unit = u"A"]    # Current flowing into the pin [A]
    @icon "pin.png"
end

@named p = Pin(; v = π)
@test getdefault(p.v) == π
@test Pin.isconnector == true

@mtkmodel OnePort begin
    @components begin
        p = Pin()
        n = Pin()
    end
    @variables begin
        v(t), [unit = u"V"]
        i(t), [unit = u"A"]
    end
    @icon "oneport.png"
    @equations begin
        v ~ p.v - n.v
        0 ~ p.i + n.i
        i ~ p.i
    end
end

@test OnePort.isconnector == false

@mtkmodel Ground begin
    @components begin
        g = Pin()
    end
    @icon read(abspath(ENV["MTK_ICONS_DIR"], "ground.svg"), String)
    @equations begin
        g.v ~ 0
    end
end

resistor_log = "$(@__DIR__)/logo/resistor.svg"
@mtkmodel Resistor begin
    @extend v, i = oneport = OnePort()
    @parameters begin
        R, [unit = u"Ω"]
    end
    @icon """<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="80" height="30">
<path d="M10 15
l15 0
l2.5 -5
l5 10
l5 -10
l5 10
l5 -10
l5 10
l2.5 -5
l15 0" stroke="black" stroke-width="1" stroke-linejoin="bevel" fill="none"></path>
</svg>
"""
    @equations begin
        v ~ i * R
    end
end

@mtkmodel Capacitor begin
    @parameters begin
        C, [unit = u"F"]
    end
    @extend OnePort(; v = 0.0)
    @icon "https://upload.wikimedia.org/wikipedia/commons/7/78/Capacitor_symbol.svg"
    @equations begin
        D(v) ~ i / C
    end
end

@named capacitor = Capacitor(C = 10, v = 10.0)
@test getdefault(capacitor.v) == 10.0

@mtkmodel Voltage begin
    @extend v, i = oneport = OnePort()
    @components begin
        V = RealInput()
    end
    @equations begin
        v ~ V.u
    end
end

@mtkmodel RC begin
    @structural_parameters begin
        R_val = 10
        C_val = 10
        k_val = 10
    end
    @components begin
        resistor = Resistor(; R = R_val)
        capacitor = Capacitor(; C = C_val)
        source = Voltage()
        constant = Constant(; k = k_val)
        ground = Ground()
    end

    @equations begin
        connect(constant.output, source.V)
        connect(source.p, resistor.p)
        connect(resistor.n, capacitor.p)
        connect(capacitor.n, source.n, ground.g)
    end
end

C_val = 20
R_val = 20
res__R = 100
@mtkbuild rc = RC(; C_val, R_val, resistor.R = res__R)
resistor = getproperty(rc, :resistor; namespace = false)
@test getname(rc.resistor) === getname(resistor)
@test getname(rc.resistor.R) === getname(resistor.R)
@test getname(rc.resistor.v) === getname(resistor.v)
# Test that `resistor.R` overrides `R_val` in the argument.
@test getdefault(rc.resistor.R) == res__R != R_val
# Test that `C_val` passed via argument is set as default of C.
@test getdefault(rc.capacitor.C) == C_val
# Test that `k`'s default value is unchanged.
@test getdefault(rc.constant.k) == RC.structure[:kwargs][:k_val]
@test getdefault(rc.capacitor.v) == 0.0

@test get_gui_metadata(rc.resistor).layout == Resistor.structure[:icon] ==
      read(joinpath(ENV["MTK_ICONS_DIR"], "resistor.svg"), String)
@test get_gui_metadata(rc.ground).layout ==
      read(abspath(ENV["MTK_ICONS_DIR"], "ground.svg"), String)
@test get_gui_metadata(rc.capacitor).layout ==
      URI("https://upload.wikimedia.org/wikipedia/commons/7/78/Capacitor_symbol.svg")
@test OnePort.structure[:icon] ==
      URI("file:///" * abspath(ENV["MTK_ICONS_DIR"], "oneport.png"))
@test ModelingToolkit.get_gui_metadata(rc.resistor.p).layout == Pin.structure[:icon] ==
      URI("file:///" * abspath(ENV["MTK_ICONS_DIR"], "pin.png"))

@test length(equations(rc)) == 1

@testset "Parameters and Structural parameters in various modes" begin
    @mtkmodel MockModel begin
        @parameters begin
            a
            a2[1:2]
            b(t)
            b2(t)[1:2]
            cval
            jval
            kval
            c(t) = cval + jval
            d = 2
            d2[1:2] = 2
            e, [description = "e"]
            e2[1:2], [description = "e2"]
            f = 3, [description = "f"]
            h(t), [description = "h(t)"]
            h2(t)[1:2], [description = "h2(t)"]
            i(t) = 4, [description = "i(t)"]
            j(t) = jval, [description = "j(t)"]
            k = kval, [description = "k"]
            l(t)[1:2, 1:3] = 2, [description = "l is more than 1D"]
        end
        @structural_parameters begin
            m = 1
            func
        end
    end

    kval = 5
    @named model = MockModel(; b2 = 3, kval, cval = 1, func = identity)

    @test lastindex(parameters(model)) == 29

    @test all(getdescription.([model.e2...]) .== "e2")
    @test all(getdescription.([model.h2...]) .== "h2(t)")

    @test hasmetadata(model.e, VariableDescription)
    @test hasmetadata(model.f, VariableDescription)
    @test hasmetadata(model.h, VariableDescription)
    @test hasmetadata(model.i, VariableDescription)
    @test hasmetadata(model.j, VariableDescription)
    @test hasmetadata(model.k, VariableDescription)
    @test all(collect(hasmetadata.(model.l, ModelingToolkit.VariableDescription)))

    @test all(lastindex.([model.a2, model.b2, model.d2, model.e2, model.h2]) .== 2)
    @test size(model.l) == MockModel.structure[:parameters][:l][:size] == (2, 3)

    model = complete(model)
    @test getdefault(model.cval) == 1
    @test isequal(getdefault(model.c), model.cval + model.jval)
    @test getdefault(model.d) == 2
    @test_throws KeyError getdefault(model.e)
    @test getdefault(model.f) == 3
    @test getdefault(model.i) == 4
    @test all(getdefault.(scalarize(model.b2)) .== 3)
    @test all(getdefault.(scalarize(model.l)) .== 2)
    @test isequal(getdefault(model.j), model.jval)
    @test isequal(getdefault(model.k), model.kval)
end

@testset "Defaults of subcomponents MTKModel" begin
    @mtkmodel A begin
        @parameters begin
            p
        end
        @components begin
            b = B(i = p, j = 1 / p, k = 1)
        end
    end

    @mtkmodel B begin
        @parameters begin
            i
            j
            k
        end
    end

    @named a = A(p = 10)
    params = get_ps(a)
    @test isequal(getdefault(a.b.i), params[1])
    @test isequal(getdefault(a.b.j), 1 / params[1])
    @test getdefault(a.b.k) == 1

    @named a = A(p = 10, b.i = 20, b.j = 30, b.k = 40)
    @test getdefault(a.b.i) == 20
    @test getdefault(a.b.j) == 30
    @test getdefault(a.b.k) == 40
end

@testset "Metadata in variables" begin
    metadata = Dict(:description => "Variable to test metadata in the Model.structure",
        :input => true, :bounds => (-1, 1), :connection_type => :Flow, :integer => true,
        :binary => false, :tunable => false, :disturbance => true, :dist => Normal(1, 1))

    @connector MockMeta begin
        m(t),
        [description = "Variable to test metadata in the Model.structure",
            input = true, bounds = (-1, 1), connect = Flow, integer = true,
            binary = false, tunable = false, disturbance = true, dist = Normal(1, 1)]
    end

    for (k, v) in metadata
        @test MockMeta.structure[:variables][:m][k] == v
    end
end

@testset "Connector with parameters, equations..." begin
    @connector A begin
        @extend (e,) = extended_e = E()
        @icon "pin.png"
        @parameters begin
            p
        end
        @variables begin
            v(t)
        end
        @components begin
            cc = C()
        end
        @equations begin
            e ~ 0
        end
    end

    @connector C begin
        c(t)
    end

    @connector E begin
        e(t)
    end

    @named aa = A()
    @test aa.connector_type == RegularConnector()

    @test A.isconnector == true

    @test A.structure[:parameters] == Dict(:p => Dict())
    @test A.structure[:extend] == [[:e], :extended_e, :E]
    @test A.structure[:equations] == ["e ~ 0"]
    @test A.structure[:kwargs] == Dict(:p => nothing, :v => nothing)
    @test A.structure[:components] == [[:cc, :C]]
end

@testset "Conditional components, equations and parameters" begin
    @mtkmodel C begin end

    # Conditional statements inside @components, @equations
    # Conditional default value of parameters and variables
    @mtkmodel InsideTheBlock begin
        @structural_parameters begin
            flag = 1
        end
        @parameters begin
            eq = flag == 1 ? 1 : 0
            if flag == 1
                a1
            elseif flag == 2
                a2
            else
                a3
            end
        end
        @components begin
            sys0 = C()
            if flag == 1
                sys1 = C()
            elseif flag == 2
                sys2 = C()
            else
                sys3 = C()
            end
        end
        @equations begin
            eq ~ 0
            if flag == 1
                eq ~ 1
            elseif flag == 2
                eq ~ 2
            else
                eq ~ 3
            end
        end
    end

    @named in_sys_1 = InsideTheBlock()
    in_sys_1 = complete(in_sys_1)
    @named in_sys_2 = InsideTheBlock(flag = 2)
    in_sys_2 = complete(in_sys_2)
    @named in_sys_3 = InsideTheBlock(flag = 3)
    in_sys_3 = complete(in_sys_3)

    @test nameof.(parameters(in_sys_1)) == [:a1, :eq]
    @test nameof.(parameters(in_sys_2)) == [:a2, :eq]
    @test nameof.(parameters(in_sys_3)) == [:a3, :eq]

    @test nameof.(in_sys_1.systems) == [:sys1, :sys0]
    @test nameof.(in_sys_2.systems) == [:sys2, :sys0]
    @test nameof.(in_sys_3.systems) == [:sys3, :sys0]

    @test all([in_sys_1.eq ~ 0, in_sys_1.eq ~ 1] .∈ [equations(in_sys_1)])
    @test all([in_sys_2.eq ~ 0, in_sys_2.eq ~ 2] .∈ [equations(in_sys_2)])
    @test all([in_sys_3.eq ~ 0, in_sys_3.eq ~ 3] .∈ [equations(in_sys_3)])

    @test getdefault(in_sys_1.eq) == 1
    @test getdefault(in_sys_2.eq) == 0

    # Branching statement outside the begin blocks
    @mtkmodel OutsideTheBlock begin
        @structural_parameters begin
            condition = 2
        end
        @parameters begin
            a0
        end
        @components begin
            sys0 = C()
        end
        @equations begin
            a0 ~ 0
        end

        if condition == 1
            @parameters begin
                a1
            end
            @equations begin
                a1 ~ 0
            end
            @components begin
                sys1 = C()
            end
        elseif condition == 2
            @parameters begin
                a2
            end
            @equations begin
                a2 ~ 0
            end
            @components begin
                sys2 = C()
            end
        else
            @parameters begin
                a3
            end
            @equations begin
                a3 ~ 0
            end
            @components begin
                sys3 = C()
            end
        end
    end

    @named out_sys_1 = OutsideTheBlock(condition = 1)
    out_sys_1 = complete(out_sys_1)
    @named out_sys_2 = OutsideTheBlock(condition = 2)
    out_sys_2 = complete(out_sys_2)
    @named out_sys_3 = OutsideTheBlock(condition = 10)
    out_sys_3 = complete(out_sys_3)

    @test nameof.(out_sys_1.systems) == [:sys1, :sys0]
    @test nameof.(out_sys_2.systems) == [:sys2, :sys0]
    @test nameof.(out_sys_3.systems) == [:sys3, :sys0]

    @test Equation[out_sys_1.a1 ~ 0
        out_sys_1.a0 ~ 0] == equations(out_sys_1)
    @test Equation[out_sys_2.a2 ~ 0
        out_sys_1.a0 ~ 0] == equations(out_sys_2)
    @test Equation[out_sys_3.a3 ~ 0
        out_sys_1.a0 ~ 0] == equations(out_sys_3)
end
