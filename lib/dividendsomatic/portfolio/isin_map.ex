defmodule Dividendsomatic.Portfolio.IsinMap do
  @moduledoc """
  Static ISIN mappings for well-known tickers not resolvable from
  holdings or dividend rows. Shared between SoldPositionProcessor
  and backfill tasks.
  """

  @static_map %{
    "AIO" => "US92838Y1029",
    "AQN" => "CA0158571053",
    "ARR" => "US0423155078",
    "AXL" => "US0240611030",
    "BABA" => "US01609W1027",
    "BIIB" => "US09062X1037",
    "BST" => "US09260D1081",
    "CCJ" => "CA13321L1085",
    "CGBD" => "US14316A1088",
    "CHCT" => "US20369C1062",
    "CTO" => "US1264081035",
    "DFN" => "CA25490A1084",
    "DHT" => "MHY2065G1219",
    "ECC" => "US26982Y1091",
    "ENB" => "CA29250N1050",
    "ET" => "US29273V1008",
    "FCX" => "US35671D8570",
    "FSZ" => "CA31660A1049",
    "GILD" => "US3755581036",
    "GNK" => "MHY2685T1313",
    "GOLD" => "CA0679011084",
    "GSBD" => "US38147U1016",
    "HTGC" => "US4271143047",
    "HYT" => "US09255P1075",
    "IAF" => "US0030281010",
    "KMF" => "US48661E1082",
    "NAT" => "BMG657731060",
    "NEWT" => "US65253E1010",
    "OCCI" => "US67111Q1076",
    "OCSL" => "US67401P1084",
    "OMF" => "US68268W1036",
    "ORA" => "FR0000133308",
    "ORCC" => "US69121K1043",
    "OXY" => "US6745991058",
    "PBR" => "US71654V4086",
    "PRA" => "US74267C1062",
    "REI.UN" => "CA7669101031",
    "RNP" => "US19247X1000",
    "SACH PRA" => "US78590A2079",
    "SBRA" => "US78573L1061",
    "SBSW" => "US82575P1075",
    "SCCO" => "US84265V1052",
    "SSSS" => "US86885M1053",
    "TDS PRU" => "US87943P1030",
    "TDS PRV" => "US87943P2020",
    "TEF" => "US8793822086",
    "TELL" => "US87968A1043",
    "TY" => "US8955731080",
    "UMH" => "US9030821043",
    "UUUU" => "CA2926717083",
    "WF" => "US98105F1049",
    "XFLT" => "US98400U1016",
    "ZM" => "US98980L1017",
    "ZTR" => "US92837G1004"
  }

  @doc "Returns the static ticker→ISIN mapping."
  def static_map, do: @static_map
end
