#
# (C) Copyright 2018 Xilinx, Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#

proc generate {drv_handle} {
	foreach i [get_sw_cores device_tree] {
		set common_tcl_file "[get_property "REPOSITORY" $i]/data/common_proc.tcl"
		if {[file exists $common_tcl_file]} {
			source $common_tcl_file
			break
		}
	}

	set node [gen_peripheral_nodes $drv_handle]
	if {$node == 0} {
		return
	}
	set compatible [get_comp_str $drv_handle]
	set compatible [append compatible " " "xlnx,mixer-3.0"]
	set_drv_prop $drv_handle compatible "$compatible" stringlist
	set ip [get_cells -hier $drv_handle]
	set num_layers [get_property CONFIG.NR_LAYERS [get_cells -hier $drv_handle]]
	hsi::utils::add_new_dts_param "${node}" "xlnx,num-layers" $num_layers int
	set samples_per_clock [get_property CONFIG.SAMPLES_PER_CLOCK [get_cells -hier $drv_handle]]
	hsi::utils::add_new_dts_param "${node}" "xlnx,ppc" $samples_per_clock int
	set max_data_width [get_property CONFIG.MAX_DATA_WIDTH [get_cells -hier $drv_handle]]
	hsi::utils::add_new_dts_param "${node}" "xlnx,bpc" $max_data_width int
	set logo_layer [get_property CONFIG.LOGO_LAYER [get_cells -hier $drv_handle]]
	if {[string match -nocase $logo_layer "true"]} {
		hsi::utils::add_new_dts_param "$node" "xlnx,logo-layer" ""  boolean
	}
	set ip_type ""
	set connected_ip_type ""
	set mixer_port_node [add_or_get_dt_node -n "port" -l crtc_mixer_port -u 0 -p $node]
	hsi::utils::add_new_dts_param "$mixer_port_node" "reg" 0 int
	set mixer_crtc [add_or_get_dt_node -n "endpoint" -l mixer_crtc -p $mixer_port_node]
	set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "m_axis_video"]
	if {[llength $connected_ip] != 0} {
		set connected_ip_type [get_property IP_NAME $connected_ip]
	}
	if {[llength $connected_ip_type] != 0} {
		if {[string match -nocase $connected_ip_type "axis_subset_converter"]} {
			set ip [hsi::utils::get_connected_stream_ip $connected_ip "M_AXIS"]
			set ip_type [get_property IP_NAME $ip]
		}
		if {[string match -nocase $connected_ip_type "mipi_dsi_tx_subsystem"]} {
			hsi::utils::add_new_dts_param "$mixer_crtc" "remote-endpoint" dsi_encoder reference
		}
		if {[string match -nocase $connected_ip_type "v_hdmi_tx_ss"]} {
			hsi::utils::add_new_dts_param "$mixer_crtc" "remote-endpoint" hdmi_encoder reference
		}
		if {[string match -nocase $connected_ip_type "v_smpte_uhdsdi_tx_ss"]|| [string match -nocase $ip_type "v_smpte_uhdsdi_tx_ss"]} {
			hsi::utils::add_new_dts_param "$mixer_crtc" "remote-endpoint" sdi_encoder reference
		}
	}

	for {set layer 0} {$layer < $num_layers} {incr layer} {
		switch $layer {
			"0" {
				set mixer_node0 [add_or_get_dt_node -n "layer$layer" -l xx_mix_master -p $node]
				hsi::utils::add_new_dts_param "$mixer_node0" "xlnx,layer-id" $layer int
				set maxwidth [get_property CONFIG.MAX_COLS [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node0" "xlnx,layer-max-width" $maxwidth int
				set maxheight [get_property CONFIG.MAX_ROWS [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node0" "xlnx,layer-max-height" $maxheight int
				hsi::utils::add_new_dts_param "$mixer_node0" "xlnx,layer-primary" "" boolean
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video"]
				if {[llength $connected_ip] != 0} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node0 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node0 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node0" "xlnx,layer-streaming" "" boolean
					}
					set layer0_video_format [get_property CONFIG.VIDEO_FORMAT [get_cells -hier $drv_handle]]
					gen_video_format $layer0_video_format $mixer_node0 $drv_handle $max_data_width
				}
			}
			"1" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer1_alpha [get_property CONFIG.LAYER1_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer1_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer1_maxwidth [get_property CONFIG.LAYER1_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer1_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video1"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER1_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer1_video_format [get_property CONFIG.LAYER1_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer1_video_format $mixer_node1 $drv_handle $max_data_width
			}
			"2" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer2_alpha [get_property CONFIG.LAYER2_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer2_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer2_maxwidth [get_property CONFIG.LAYER2_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer2_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video2"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER2_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer2_video_format [get_property CONFIG.LAYER2_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer2_video_format $mixer_node1 $drv_handle $max_data_width
			}
			"3" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer3_alpha [get_property CONFIG.LAYER3_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer3_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer3_maxwidth [get_property CONFIG.LAYER3_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer3_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video3"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER3_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer3_video_format [get_property CONFIG.LAYER3_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer3_video_format $mixer_node1 $drv_handle $max_data_width
			}
			"4" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer4_alpha [get_property CONFIG.LAYER4_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer4_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer4_maxwidth [get_property CONFIG.LAYER4_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer4_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video4"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER4_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer4_video_format [get_property CONFIG.LAYER4_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer4_video_format $mixer_node1 $drv_handle $max_data_width
			}
			"5" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer5_alpha [get_property CONFIG.LAYER5_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer5_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer5_maxwidth [get_property CONFIG.LAYER5_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer5_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video5"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER5_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer5_video_format [get_property CONFIG.LAYER5_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer5_video_format $mixer_node1 $drv_handle $max_data_width
			}
			"6" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer6_alpha [get_property CONFIG.LAYER6_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer6_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer6_maxwidth [get_property CONFIG.LAYER6_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer6_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video6"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER6_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer6_video_format [get_property CONFIG.LAYER6_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer6_video_format $mixer_node1 $drv_handle $max_data_width
			}
			"7" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer7_alpha [get_property CONFIG.LAYER7_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer7_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer7_maxwidth [get_property CONFIG.LAYER7_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer7_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video7"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER7_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer7_video_format [get_property CONFIG.LAYER7_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer7_video_format $mixer_node1 $drv_handle $max_data_width
			}
			"8" {
				set mixer_node1 [add_or_get_dt_node -n "layer$layer" -l xx_mix_overlay_$layer -p $node]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
				set layer8_alpha [get_property CONFIG.LAYER8_ALPHA [get_cells -hier $drv_handle]]
				if {[string match -nocase $layer8_alpha "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-alpha" "" boolean
				}
				set layer8_maxwidth [get_property CONFIG.LAYER8_MAX_WIDTH [get_cells -hier $drv_handle]]
				hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $layer8_maxwidth int
				set connected_ip [hsi::utils::get_connected_stream_ip [get_cells -hier $drv_handle] "s_axis_video8"]
				if {[llength $connected_ip]} {
					set connected_ip_type [get_property IP_NAME $connected_ip]
					if {[string match -nocase $connected_ip_type "v_frmbuf_rd"]} {
						hsi::utils::add_new_dts_param $mixer_node1 "dmas" "$connected_ip 0" reference
						hsi::utils::add_new_dts_param $mixer_node1 "dma-names" "dma0" string
						hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-streaming" "" boolean
					}
				}
				set sample [get_property CONFIG.LAYER8_UPSAMPLE [get_cells -hier $drv_handle]]
				if {[string match -nocase $sample "true"]} {
					hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-scale" "" boolean
				}
				set layer8_video_format [get_property CONFIG.LAYER8_VIDEO_FORMAT [get_cells -hier $drv_handle]]
				gen_video_format $layer8_video_format $mixer_node1 $drv_handle $max_data_width
			}
			default {
			}
		}
	}
	set mixer_node1 [add_or_get_dt_node -n "logo" -l xx_mix_logo -p $node]
	hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-id" $layer int
	set logo_width [get_property CONFIG.MAX_LOGO_COLS [get_cells -hier $drv_handle]]
	hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-width" $logo_width int
	set logo_height [get_property CONFIG.MAX_LOGO_ROWS [get_cells -hier $drv_handle]]
	hsi::utils::add_new_dts_param "$mixer_node1" "xlnx,layer-max-height" $logo_height int
	set pins [get_pins -of_objects [get_nets -of_objects [get_pins -of_objects $ip "ap_rst_n"]]]
	foreach pin $pins {
		set sink_periph [::hsi::get_cells -of_objects $pin]
		set sink_ip [get_property IP_NAME $sink_periph]
		if {[string match -nocase $sink_ip "xlslice"]} {
			set gpio [get_property CONFIG.DIN_FROM $sink_periph]
			set pins [get_pins -of_objects [get_nets -of_objects [get_pins -of_objects $sink_periph "Din"]]]
			foreach pin $pins {
				set periph [::hsi::get_cells -of_objects $pin]
				set ip [get_property IP_NAME $periph]
				set proc_type [get_sw_proc_prop IP_NAME]
				if {[string match -nocase $proc_type "psu_cortexa53"] } {
					if {[string match -nocase $ip "zynq_ultra_ps_e"]} {
						set gpio [expr $gpio + 78]
						hsi::utils::add_new_dts_param "$node" "reset-gpios" "gpio $gpio 1" reference
					}
				}
				if {[string match -nocase $ip "axi_gpio"]} {
					hsi::utils::add_new_dts_param "$node" "reset-gpios" "$periph $gpio 0 1" reference
				}
			}
		}
	}
}

proc gen_video_format {num node drv_handle max_data_width} {
	switch $num {
		"0" {
			append vid_formats " " "bg24"
		}
		"1" {
			append vid_formats " " "yuyv"
		}
		"2" {
			if {$max_data_width == 10} {
				append vid_formats " " "xv20"
			} else {
				append vid_formats " " "nv16"
			}
		}
		"3" {
			if {$max_data_width == 10} {
				append vid_formats " " "xv15"
			} else {
				append vid_formats " " "nv12"
			}
		}
		"5" {
			append vid_formats " " "rgb888"
		}
		"6" {
			append vid_formats " " "rgb888"
		}
		"10" {
			append vid_formats " " "xbgr8888"
		}
		"11" {
			append vid_formats " " "xvuy8888"
		}
		"12" {
			append vid_formats " " "yuyv"
		}
		"13" {
			append vid_formats " " "abgr8888"
		}
		"14" {
			append vid_formats " " "avuy8888"
		}
		"15" {
			append vid_formats " " "xbgr2101010"
		}
		"16" {
			append vid_formats " " "yuvx2101010"
		}
		"17" {
			append vid_formats " " "xxxxx"
		}
		"18" {
			append vid_formats " " "nv16"
		}
		"19" {
			append vid_formats " " "nv12"
		}
		"20" {
			append vid_formats " " "bgr888"
		}
		"21" {
			append vid_formats " " "vuy888"
		}
		"22" {
			append vid_formats " " "xxxxx"
		}
		"23" {
			append vid_formats " " "xv15"
		}
		"24" {
			append vid_formats " " "y8"
		}
		"25" {
			append vid_formats " " "y10"
		}
		"26" {
			append vid_formats " " "argb8888"
		}
		"27" {
			append vid_formats " " "xrgb8888"
		}
		"28" {
			append vid_formats " " "uyvy"
		}
	}
	hsi::utils::add_new_dts_param "$node" "xlnx,video-format" $vid_formats stringlist
}
