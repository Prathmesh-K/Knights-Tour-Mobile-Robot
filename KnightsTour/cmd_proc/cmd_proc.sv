///////////////////////////////////////////////////
// cmd_proc.sv                                   //
// This is the command processing unit of        //
// the Knight robot dictating how it should      //
// respond given a command from a Bluetooth      //
// module.                                       //
///////////////////////////////////////////////////
module cmd_proc(
    clk, rst_n, cmd, y_offset, cmd_rdy, clr_cmd_rdy, send_resp, strt_cal,
    cal_done, heading, heading_rdy, lftIR, cntrIR, rghtIR, error,
    frwrd, moving, tour_go, fanfare_go
);

  parameter FAST_SIM = 1;                 // speeds up incrementing of frwrd register for faster simulation

  input         clk, rst_n;               // 50MHz clock and asynch active low reset
  input [15:0]  cmd;                      // command from BLE
  input         cmd_rdy;                  // command ready
  output logic  clr_cmd_rdy;              // mark command as consumed
  output logic  send_resp;                // command finished, send_response via UART_wrapper/BT
  output logic [2:0] y_offset;            // calibrated y-offset of the Knight (when CALY is asserted)

  output logic  strt_cal;                 // initiate calibration of gyro
  input         cal_done;                 // calibration of gyro done
  input signed [11:0] heading;            // heading from gyro
  input         heading_rdy;              // pulses high 1 clk for valid heading reading

  output logic  moving;                   // asserted when moving (allows yaw integration)

  output reg signed [11:0] error;         // error to PID (heading - desired_heading)
  output reg [9:0] frwrd;                 // forward speed register
  
  input         lftIR;                    // nudge error +
  input         cntrIR;                   // center IR reading (have I passed a line)
  input         rghtIR;                   // nudge error -

  output logic  tour_go;                  // pulse to initiate TourCmd block
  output logic  fanfare_go;               // kick off the "Charge!" fanfare on piezo

  ////////////////////////////////////////
  // Declare state types as enumerated //
  //////////////////////////////////////
  typedef enum logic [2:0] {IDLE, CALIBRATE, MOVE, INCR, DECR, REVERSE, BACKUP} state_t;

  ////////////////////////////////////////////
  // Declare command opcodes as enumerated //
  //////////////////////////////////////////
  typedef enum logic [3:0] {CAL = 4'b0010, MOV = 4'b0100, FANFARE = 4'b0101, TOUR = 4'b0110, CALY = 4'b0111} op_t;

  ///////////////////////////////////
  // Declare any internal signals //
  /////////////////////////////////
  ////////////////////////////// Forward Register Logic ////////////////////////////////////
  logic zero;                          // The forward register is zero when cleared or decremented all the way.
  logic max_spd;                       // The forward register has reached its max speed when the 2 most significant bits are ones.
  logic [6:0] inc_amt;                 // Amount of speed to increase/ramp up each clock cycle.
  logic [6:0] dec_amt;                 // Amount of speed to decrease/ramp down each clock cycle.
  ///////////////////////// Square Count Logic ////////////////////////////////////////////
  logic [4:0] pulse_cnt;               // Indicates number of times cntrIR went high when moving the Knight, max 16 times.
  logic [3:0] square_cnt;              // The number of squares the Knight moved on the board.
  logic move_done;                     // Indicates that a move is completed by the Knight.
  logic cntrIR_prev;                   // Previous cntrIR signal from the IR sensor.
  //////////////////////// Y-Calibration Logic ////////////////////////////////////////////
  logic [3:0] y_pos;                   // Indicates the current y-position of the Knight from the start of the board.
  logic fall_edge_pulse;               // Used to know when the Knight is off the board.
  logic square_done;                   // Indicates that one single square has been moved by the Knight
  logic came_back;                     // Indicates that the Knight returned to the original position after calibration.
  ////////////////////////////// PID Interface Logic ////////////////////////////////////
  logic signed [11:0] desired_heading; // Compute the desired heading based on the command given.
  logic signed [11:0] err_nudge;       // An error offset term to correct for when the robot wanders.
  logic [11:0] error_abs;              // Absolute value of the error.
  ///////////////////////////// State Machine ////////////////////////////////////////////
  logic move_cmd;                      // The command that tells Knight to move from the state machine.
  logic calibrate_y;                   // Indicates calibration of the y-position of the Knight.
  logic reverse_heading;               // Indicates that we are reversing the heading of the Knight.
  logic moving_back;                   // Indicates that we are moving the Knight backwards.
  logic clr_frwrd;                     // Tells the Knight to ramp up its speed starting from 0.
  logic inc_frwrd;                     // Tells the Knight to ramp up its speed.
  logic dec_frwrd;                     // Tells the Knight to decrease up its speed.
  op_t opcode;                         // Opcode held in cmd[15:12].
  state_t state;                       // Holds the current state.
  state_t nxt_state;                   // Holds the next state.
  ////////////////////////////////////////////////////////////////////////////////////////

  ///////////////////////////////////////////////////////////
  // Implements forward speed register to move the Knight //
  /////////////////////////////////////////////////////////
  // The forward register is zero when cleared.
  assign zero = (frwrd == 10'h000);

  // The forward register has reached its max speed 
  // when the 2 most significant bits are ones.
  assign max_spd = &frwrd[9:8];

  // Implement the forward speed register of the Knight to move it forward or slow down.
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n)
      frwrd <= 10'h000; // Clear the register asynchronously.
    else if (clr_frwrd)
      frwrd <= 10'h000; // Clear the register when we are beginning a movement.
    else if (heading_rdy) begin // Only increment or decrement the forward register when a new heading is ready.
      if (inc_frwrd) begin
        if (!max_spd) 
          // Only increment the register if we are not at the max speed.  
          frwrd <= frwrd + inc_amt;
      end else if (dec_frwrd) begin
        if (!zero)
          // Only decrement the register if we are not at the minimum speed.  
          frwrd <= frwrd - dec_amt;
      end
    end
  end

  generate // Increment frwrd by different amounts based on whether FAST_SIM is enabled.
    if (FAST_SIM)
      assign inc_amt = 7'h20;
    else 
      assign inc_amt = 7'h03;
  endgenerate

  generate // Decrement frwrd by different amounts based on whether FAST_SIM is enabled.
    if (FAST_SIM)
      assign dec_amt = (opcode == CALY) ? 7'h35 : 7'h40;
    else 
      assign dec_amt = (opcode == CALY) ? 7'h04 : 7'h06;
  endgenerate
  //////////////////////////////////////////////////////////////////////////
 
  ////////////////////////////////////////////////////////
  // Counts the number of squares the Knight has moved //
  //////////////////////////////////////////////////////
  // Implement rising edge detector to check when cntrIR pulse goes high.
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n)
      cntrIR_prev <= 1'b0;   // Reset the cntrIR_prev value.
    else
      cntrIR_prev <= cntrIR; // Used to detect rising edge on cntrIR pulse.
  end

  // A pulse is detected from the cntrIR sensor when the previous value was low and current value is high.
  assign pulse_detected = ~cntrIR_prev & cntrIR;

  // Implement register to load the number squares to be moved by the Knight.
  always_ff @(posedge clk) begin
    if (opcode == CALY) begin // We only care about the below if the opcode is CALY.
      if (calibrate_y)
        square_cnt <= 4'h1; // By default, we move one square at a time till off the board to calibrate the y-position.
      else if (reverse_heading)
        square_cnt <= y_pos; // Load in y_pos to move the Knight back to the original starting location.
    end else if (move_cmd)
      square_cnt <= cmd[3:0]; // Load in the number of squares to move when the command is asserted.
  end

  // Implement counter to count number of times the cntrIR pulse went high. 
  always_ff @(posedge clk) begin
    if (move_cmd | calibrate_y)
      pulse_cnt <= 5'h0; // Reset to 0 initially when begining a move or moving forward to calibrate the y-position.
    else if (reverse_heading)
      pulse_cnt <= 5'h1; // When we are reversing the Knight, load in one as we won't see two pulses on the way back.
    else if (pulse_detected)
      pulse_cnt <= pulse_cnt + 1'b1; // Increment the pulse count whenever we detect that cntrIR went high.
  end

  // Grab opcode that is being held in cmd.
  assign opcode = op_t'(cmd[15:12]);

  // Compare whether the pulse count detected is 2 times the number of sqaures requested to move,
  // to indicate that a move is complete.
  assign move_done = (pulse_cnt == {square_cnt, 1'b0});
  //////////////////////////////////////////////////////////////////////////

  /////////////////////////////////////////////////////////////////////////
  // Calibrates the y-offset of the Knight to get the starting position //
  ///////////////////////////////////////////////////////////////////////
  // Implement counter to track the offset of the Knight from the end of the board.
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n)
      y_pos <= 4'h0; // Reset the offset to zero initially.
    else if (opcode == CALY) begin // We only care about this register if the opcode is CALY.
      if (square_done) begin // Increment or decrement the counter based on moving forward or backward.
        if (moving_back)
          y_pos <= y_pos - 1'b1; // Decrement the offset as we are heading back.
        else
          y_pos <= y_pos + 1'b1; // Increment the offset to know how far the Knight is from the end of the board.
      end
    end
  end
  
  // Indicates that the Knight moved a single sqaure in the reverse direction, if the pulse count is a multiple of two.
  assign square_done = (~pulse_cnt[0]);

  // A fall-edge detector on cntrIR to know when we are off the board. We expect the cntrIR signal to previously be high
  // but go low within a square after coming to a stop.
  assign fall_edge_pulse = cntrIR_prev & ~cntrIR; 

  // We came back to the starting location when the offset reached zero.
  assign came_back = (y_pos == 4'h0);

  // Concatenate the incoming command with the correct offset after calibration.
  assign y_offset = (opcode == CALY) ? (4'h5 - square_cnt) : cmd[2:0]; 
  /////////////////////////////////////////////////////////////////////////////////

  /////////////////////////////////////////////////////////////////////////
  // Interfaces with the PID to move the Knight in the right direction  //
  ///////////////////////////////////////////////////////////////////////
  // Form the nudge factor based on whether the Knight veers too much to the left or right. 
  generate
    // Generate a different nudge factor when FAST_SIM is enabled.
    if (FAST_SIM)
      // Whenever lftIR goes high we add a positive nudge factor, and whenever rghtIR goes high,
      // we add a negative nudge factor.
      assign err_nudge = (lftIR)  ? 12'h1FF : 
		                     (rghtIR) ? 12'hE00 : 
                         12'h000;
    else
      assign err_nudge = (lftIR)  ? 12'h05F : 
	                       (rghtIR) ? 12'hFA1 : 
                         12'h000;
  endgenerate

  // Compute the desired heading based on the command.
  always_ff @(posedge clk) begin
    if (opcode == CALY) begin // We only care about the below condition if the opcode is CALY.
      if (calibrate_y)
          desired_heading <= 12'h000; // We always move north to calibrate the y-position.
      else if (reverse_heading)
          desired_heading <= 12'h7FF; // Rotate the Knight CW by 180 degrees to now face south.
    end else if (move_cmd) begin // If the Knight is required to move, take the heading from the command.
      if (cmd[11:4] == 8'h00)
        desired_heading <= 12'h000;
      else
        desired_heading <= {cmd[11:4], 4'hF}; // If desired heading is non-zero append 0xF to form the desired heading.
    end 
  end

  // Form the error term as the difference of the actual and desired heading with the nudge factor.
  assign error = heading - desired_heading + err_nudge;

  // Computes the absolute value of the error.
  assign error_abs = (error[11]) ? -error : error;
  //////////////////////////////////////////////////////////////////////////

  /////////////////////////////////////
  // Implements State Machine Logic //
  ///////////////////////////////////
  // Implements state machine register, holding current state or next state, accordingly.
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n)
      state <= IDLE; // Reset into the idle state if machine is reset.
    else
      state <= nxt_state; // Store the next state as the current state by default.
  end

  //////////////////////////////////////////////////////////////////////////////////////////
  // Implements the combinational state transition and output logic of the state machine.//
  ////////////////////////////////////////////////////////////////////////////////////////
  always_comb begin
    /* Default all SM outputs & nxt_state */
    nxt_state = state;      // By default, assume we are in the current state.
    strt_cal = 1'b0;        // By default, do not start calibration of the gyro.
    move_cmd = 1'b0;        // By default, we are not processing a move command.
    calibrate_y = 1'b0;     // By default, we are not calibrating the y-position of the Knight.
    reverse_heading = 1'b0; // By default, we are not reversing the heading of the Knight.
    moving = 1'b0;          // By default, the Knight is not moving.
    moving_back = 1'b0;     // By default, we are not moving backwards.
    clr_frwrd = 1'b0;       // By default, the forward speed register is not cleared.
    inc_frwrd = 1'b0;       // By default, we are not incrementing the forward speed register.
    dec_frwrd = 1'b0;       // By default, we are not decrementing the forward speed register.
    tour_go = 1'b0;         // By default, we are not starting the Knight's tour.
    send_resp = 1'b0;       // By default, we are not sending an acknowledgment to the sender.
    fanfare_go = 1'b0;      // By default, we are not moving the Knight with fanfare.
    clr_cmd_rdy = 1'b0;     // By default, we are not clearing the command as read.

    case (state)
      CALIBRATE : begin // State for calibration process.
        if (cal_done) begin // Wait until calibration is complete.
          send_resp = 1'b1; // Send acknowledgment to Bluetooth.
          nxt_state = IDLE; // Return to IDLE.
        end
      end

      MOVE : begin // State to start moving.
        if (opcode == CALY)
            calibrate_y = 1'b1; // Command to calibrate the y-position of the Knight.
        else 
          move_cmd = 1'b1; // Command to move normally.
        if (error_abs < 12'h02C) begin
          moving = 1'b1;    // We only move when the absolute value of the error is within the threshold.
          clr_frwrd = 1'b1; // Clear the forward register.
          nxt_state = INCR; // Move to the increment speed state.
        end
      end

      INCR : begin // State to increment speed.
        inc_frwrd = 1'b1; // Increment forward speed.
        moving = 1'b1; // Continue moving.
        if (move_done) begin // If movement is complete.
          if (opcode == FANFARE) // If we move with fanfare, play the tune.
            fanfare_go = 1'b1; // Turn on fanfare for special move.
          nxt_state = DECR; // Go to the decrement speed state.
        end 
      end

      DECR : begin // State to decrement speed.
        dec_frwrd = 1'b1; // Decrement speed.
        if (zero) begin // If forward speed reaches zero.
          if (opcode == CALY) begin // If we are calibrating the y-position, we need to check if the Knight is off the board.
            if (!fall_edge_pulse) // If the Knight came to a stop but did not detect a falling edge on cntrIR, it means the Knight is off the board.
              nxt_state = REVERSE; // Head to the REVERSE state to reverse the heading of the Knight CW by 180 degrees. 
            else
              if (came_back) begin // This is only true if we returned back to the starting position.
                tour_go = 1'b1; // Assert tour_go once the y-position has been found and return to IDLE.
                nxt_state = IDLE; // Return to IDLE.
              end
              else
                nxt_state = MOVE; // If we are not yet off the board or did not return to the starting position, keep moving forward by one square.
          end 
          else begin
            send_resp = 1'b1; // Send acknowledgment to Bluetooth if this was a normal move.
            nxt_state = IDLE; // Return to IDLE.
          end
        end 
        else
          moving = 1'b1; // Continue moving if not zero.
      end

      REVERSE : begin // Reverse the heading of the Knight by 90 degrees CW.
        reverse_heading = 1'b1; // Reverse the heading of the Knight again by 180 degrees.
        if (error_abs < 12'h02C) begin
          moving = 1'b1; // We only move when the absolute value of the error is within the threshold.
          moving_back = 1'b1; // Indicate that we are moving backwards.
          clr_frwrd = 1'b1; // Clear the forward register.
          nxt_state = BACKUP; // Move to the backup state.
        end
      end

      BACKUP : begin // State to move foraward in the reverse direction.
        inc_frwrd = 1'b1; // Increment forward speed.
        moving = 1'b1; // Continue moving.
        moving_back = 1'b1; // Signal to indicate that we are moving back.
        if (move_done) // If movement is complete.
          nxt_state = DECR; // Go to the decrement speed state. 
      end

      default : begin // IDLE state - waits for a command
        if (cmd_rdy) begin // If a command is ready split into the following states based on the opcode.
          case (opcode)
            TOUR : begin
              tour_go = 1'b1; // Enable Knight's tour.
            end
            CAL : begin
              nxt_state = CALIBRATE; // Command to start calibration.
              strt_cal = 1'b1; // Enable calibration.
            end
            default : begin // MOV, FANFARE, CALY opcodes.
              nxt_state = MOVE; // Command to move forward and slow down (optionally with fanfare).
            end
          endcase
          clr_cmd_rdy = 1'b1; // Clear the command ready signal.
        end      
      end
    endcase
  end
endmodule