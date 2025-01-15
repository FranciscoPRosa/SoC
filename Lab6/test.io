(globals
    version = 3
    io_order = default
)
(iopad
    (topright
        (inst name="CornerCell2" orientation=R90 cell="CORNERHB")
    )
    (top
        (inst name="vinIO" )         # analog input
        (inst name="vsensbatIO" )    # analog input
        (inst name="vbattempIO" )    # analog input
        (inst name="vccio" )         # digital supply
    )
    (topleft
        (inst name="CornerCell1" orientation=R180 cell="CORNERHB")
    )
    (left
        (inst name="en_pad" )        # digital en
        (inst name="sel_pad0" )      # (sel[0])
        (inst name="sel_pad1" )      # (sel[1])
        (inst name="vccinst1" )      # analog 
    )
    (bottomleft
        (inst name="CornerCell4" orientation=R270 cell="CORNERHB")
    )
    (bottom
        (inst name="iforcedbatIO" )  # analog output
        (inst name="gndio" )         # digital ground IO
        (inst name="gndinst2" )      # analog ground
    )
    (bottomright
        (inst name="CornerCell3" orientation=R0 cell="CORNERHB")
    )
    (right
        (inst name="sel_pad2" )      # sel[2]
        (inst name="sel_pad3" )      # sel[3]
        (inst name="vcc3io" )        # digital supply
    )
)
