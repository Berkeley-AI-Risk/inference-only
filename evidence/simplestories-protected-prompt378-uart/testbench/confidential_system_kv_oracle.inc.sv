    // Independent integer-cache + native OpenSSL oracle, not an RTL-derived
    // encryption scoreboard. These arrays feed only comparisons, never DDR.
    logic [63:0] kv_cipher_epoch[0:4095],kv_plain_epoch[0:4095];
    logic [18:0] kv_cipher_addr[0:4095],kv_plain_addr[0:4095];
    logic [255:0] kv_cipher_data[0:4095],kv_plain_data[0:4095];
    integer kv_cipher_count,kv_plain_count,kv_cipher_checked=0,kv_plain_checked=0;
    initial begin: load_kv_reference
        string path;
        integer fd,got,extra;
        if(!$value$plusargs("KV_CIPHER_ORACLE=%s",path)) $fatal(1,"KV_CIPHER_ORACLE required");
        fd=$fopen(path,"r");if(!fd) $fatal(1,"cannot open ciphertext oracle");
        got=$fscanf(fd,"%d\n",kv_cipher_count);
        if(got!=1 || kv_cipher_count<1 || kv_cipher_count>4096) $fatal(1,"bad cipher oracle count");
        for(integer i=0;i<kv_cipher_count;i++) begin
            got=$fscanf(fd,"%h %h %h\n",kv_cipher_epoch[i],kv_cipher_addr[i],kv_cipher_data[i]);
            if(got!=3) $fatal(1,"short cipher oracle");
        end
        got=$fscanf(fd,"%d",extra);if(got!=-1) $fatal(1,"trailing cipher oracle data");$fclose(fd);
        if(!$value$plusargs("KV_PLAIN_ORACLE=%s",path)) $fatal(1,"KV_PLAIN_ORACLE required");
        fd=$fopen(path,"r");if(!fd) $fatal(1,"cannot open plaintext oracle");
        got=$fscanf(fd,"%d\n",kv_plain_count);
        if(got!=1 || kv_plain_count<1 || kv_plain_count>4096) $fatal(1,"bad plain oracle count");
        for(integer i=0;i<kv_plain_count;i++) begin
            got=$fscanf(fd,"%h %h %h\n",kv_plain_epoch[i],kv_plain_addr[i],kv_plain_data[i]);
            if(got!=3) $fatal(1,"short plain oracle");
        end
        got=$fscanf(fd,"%d",extra);if(got!=-1) $fatal(1,"trailing plain oracle data");$fclose(fd);
    end
    always @(posedge core_clk_i) begin
        if(reset_n_i && u_uart.u_machine.guard_wr_valid && u_uart.u_machine.guard_wr_ready) begin
            if(kv_plain_checked>=kv_plain_count || u_uart.u_machine.private_kv_epoch!==kv_plain_epoch[kv_plain_checked] ||
                    u_uart.u_machine.guard_wr_shadow!==kv_plain_addr[kv_plain_checked] ||
                    u_uart.u_machine.guard_wr_data!==kv_plain_data[kv_plain_checked])
                $fatal(1,"independent plaintext KV mismatch word=%0d addr=%0d",kv_plain_checked,u_uart.u_machine.guard_wr_shadow);
            kv_plain_checked<=kv_plain_checked+1;
        end
    end
    always @(posedge phy_clk_i) begin
        if(reset_n_i && app_cmd_en && app_cmd==0 && thin_issue_runtime) begin
            if(kv_cipher_checked>=kv_cipher_count || u_uart.u_machine.private_kv_epoch!==kv_cipher_epoch[kv_cipher_checked] ||
                    app_addr[21:3]!==kv_cipher_addr[kv_cipher_checked] ||
                    app_wdata!==kv_cipher_data[kv_cipher_checked])
                $fatal(1,"external KV plaintext spill or ciphertext mismatch word=%0d addr=%0d",kv_cipher_checked,app_addr[21:3]);
            kv_cipher_checked<=kv_cipher_checked+1;
        end
    end
    task automatic check_kv_oracle_done;
        if(kv_plain_checked!=kv_plain_count || kv_cipher_checked!=kv_cipher_count ||
                kv_cipher_checked!=endpoint_kv_writes_q || kv_plain_count*10!=kv_cipher_count*9 ||
                u_uart.u_machine.kv_cipher_fault || u_uart.u_machine.kv_cipher_busy)
            $fatal(1,"ciphertext KV oracle/owner did not complete");
        $display("KV_CIPHERTEXT_ORACLE logical_words=%0d cipher_words=%0d epochs=2 native_openssl=1 guard_plaintext_sha=1",
            kv_plain_checked,kv_cipher_checked);
    endtask
