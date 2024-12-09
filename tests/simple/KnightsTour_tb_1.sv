module KnightsTour_tb();

  import tb_tasks::*;
  
  ///////////////////////////
  // Stimulus of type reg //
  /////////////////////////
  reg clk, RST_n;
  reg [15:0] cmd;
  reg send_cmd;

  ///////////////////////////////////
  // Declare any internal signals //
  /////////////////////////////////
  wire SS_n,SCLK,MOSI,MISO,INT;
  wire lftPWM1,lftPWM2,rghtPWM1,rghtPWM2;
  wire TX_RX, RX_TX;
  logic cmd_sent;
  logic resp_rdy;
  logic [7:0] resp;
  wire IR_en;
  wire lftIR_n,rghtIR_n,cntrIR_n;
  wire piezo, piezo_n;
  
  //////////////////////
  // Instantiate DUT //
  ////////////////////
  KnightsTour iDUT(.clk(clk), .RST_n(RST_n), .SS_n(SS_n), .SCLK(SCLK),
                   .MOSI(MOSI), .MISO(MISO), .INT(INT), .lftPWM1(lftPWM1),
				   .lftPWM2(lftPWM2), .rghtPWM1(rghtPWM1), .rghtPWM2(rghtPWM2),
				   .RX(TX_RX), .TX(RX_TX), .piezo(piezo), .piezo_n(piezo_n),
				   .IR_en(IR_en), .lftIR_n(lftIR_n), .rghtIR_n(rghtIR_n),
				   .cntrIR_n(cntrIR_n));
				  
  /////////////////////////////////////////////////////
  // Instantiate RemoteComm to send commands to DUT //
  ///////////////////////////////////////////////////
  RemoteComm iRMT(.clk(clk), .rst_n(RST_n), .RX(RX_TX), .TX(TX_RX), .cmd(cmd),
             .snd_cmd(send_cmd), .cmd_snt(cmd_sent), .resp_rdy(resp_rdy), .resp(resp));
				   
  //////////////////////////////////////////////////////
  // Instantiate model of Knight Physics (and board) //
  ////////////////////////////////////////////////////
  KnightPhysics iPHYS(.clk(clk),.RST_n(RST_n),.SS_n(SS_n),.SCLK(SCLK),.MISO(MISO),
                      .MOSI(MOSI),.INT(INT),.lftPWM1(lftPWM1),.lftPWM2(lftPWM2),
					  .rghtPWM1(rghtPWM1),.rghtPWM2(rghtPWM2),.IR_en(IR_en),
					  .lftIR_n(lftIR_n),.rghtIR_n(rghtIR_n),.cntrIR_n(cntrIR_n)); 
	
  ///////////////////////////////////////////////////////////
  // Test procedure to apply stimulus and check responses //
  /////////////////////////////////////////////////////////
  initial begin
    /////////////////////////////
    // Initialize all signals //
    ///////////////////////////
    Initialize(.clk(clk), .RST_n(RST_n), .send_cmd(send_cmd), .cmd(cmd));

    ///////////////////////////////////////////////
    // TEST 1: Test signals post initialization //
    /////////////////////////////////////////////
    // Check that NEMO_setup is being asserted after initialization.
    TimeoutTask(.sig(iPHYS.iNEMO.NEMO_setup), .clk(clk), .clks2wait(1000000), .signal("NEMO_setup"));
    /////////////////////////////////////////////////////////////////////////////////////////////////

    ////////////////////////////////////////////
    // TEST 2: Test signals post calibration //
    //////////////////////////////////////////
    // Send a command to calibrate the gyro of the Knight.
    SendCmd(.cmd_to_send(CAL_GYRO), .cmd(cmd), .clk(clk), .send_cmd(send_cmd), .cmd_sent(cmd_sent));

    // Check that cal_done is being asserted after calibration.
    TimeoutTask(.sig(iDUT.cal_done), .clk(clk), .clks2wait(1000000), .signal("cal_done"));

    // Check that a positive acknowledge is received from the DUT.
    ChkPosAck(.resp_rdy(resp_rdy), .clk(clk), .resp(resp));

    // If we reached here, that means all test cases were successful.
		$display("YAHOO!! All tests passed.");
		$stop();
    /////////////////////////////////////////////////////////////////////////////////////////////////
  end
  
  always
    #5 clk = ~clk;
  
endmodule


