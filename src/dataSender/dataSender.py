# dataSender for weather station box 
# Original by Hakan Saplakoglu
# Modified by Zachary Clayton 
# Added functionality to also upload data not uploaded from the previous hour due to timing issues with running this program every 20 minutes. 
# Data was lost so I made it also upload data from the previous hour not uploaded yet

import influxdb_client
from influxdb_client.client.write_api import SYNCHRONOUS
from influxdb_client.rest import InfluxDBError
import time
from datetime import datetime
from datetime import timedelta
import os
import csv
import argparse
import pandas as pd
import socket

def main():

    parser = argparse.ArgumentParser(description='Sends the past hour of data to influxdb')
    parser.add_argument("url", help="URL of influxdb remote server", type=str)
    parser.add_argument("org", help="InfluxDB Org", type=str)
    parser.add_argument("token", help="InfluxDB API token", type=str)
    parser.add_argument("bucket", help="InfluxDB Bucket name", type=str)
    parser.add_argument("-l", "--logdir", help="Log directory", action='append', required=True)
    parser.add_argument("-t", "--time", help="Send specific csv")
    parser.add_argument("-c", "--chunk", help="CSV chunk size in # of lines", default=1000)
    args = parser.parse_args()

    # create influxdb objects
    client = influxdb_client.InfluxDBClient(url=args.url, token=args.token, org=args.org)

    dev_hostname = socket.gethostname()

    if args.time is None:
        # find the start time of the previous hour
        cur_time = datetime.utcnow()
        prev_hour = cur_time - timedelta(hours=1)
    else:
        cur_time = datetime.fromisoformat(args.time)
        prev_hour = cur_time - timedelta(hours=1)
        
    csv_timestamp_prev = prev_hour.replace(minute=0, second=0, microsecond=0)
    csv_timestamp_curr = cur_time.replace(minute=0, second=0, microsecond=0)

    for logdir in args.logdir:
        log_prefix = os.path.basename(logdir)

        for csv_timestamp in [csv_timestamp_prev, csv_timestamp_curr]:  # upload data from previous hour and current hour
            csv_path = os.path.join(
                logdir,
                log_prefix + "_" + datetime.strftime(csv_timestamp, "%Y%m%d"),
                log_prefix + "_" + datetime.strftime(csv_timestamp, "%Y%m%d-%H") + ".csv"
            )

            if csv_timestamp > datetime.utcnow():
                continue  

            if not os.path.isfile(csv_path):
                print(f"CSV file not found for timestamp: {csv_timestamp}")
                continue
            
            # read csv in chunks with pandas
            if log_prefix == "BAROLOG":
                csvHeader = ["hostname", "sensor_id", "sys_timestamp", "timestamp", "value"]
            elif log_prefix == "WINDLOG":
                csvHeader = ["hostname", "sensor_id", "timestamp", "adc", "voltage", "value"]
            elif log_prefix == "ZACHLOG":
                csvHeader = ["timestamp", "RecNbr", "b'BattV'", "b'PTemp_C'" ,"b'AirTC'", "b'RH'", "b'WS_ms'", "b'WindDir'", "b'BaroPres'", "b'Pyranometer'", "zakbox" ] 
        
            for df in pd.read_csv(csv_path, chunksize=args.chunk, names=csvHeader, skiprows=1):
                # convert values
                df["RecNbr"] = df["RecNbr"].astype(float)
                df["b'BattV'"] = df["b'BattV'"].astype(float)
                df["b'PTemp_C'"] = df["b'PTemp_C'"].astype(float)
                df["b'AirTC'"] = df["b'AirTC'"].astype(float)
                df["b'RH'"] = df["b'RH'"].astype(float)
                df["b'WS_ms'"] = df["b'WS_ms'"].astype(float)
                df["b'WindDir'"] = df["b'WindDir'"].astype(float)
                df["b'BaroPres'"] = df["b'BaroPres'"].astype(float)
                df["b'Pyranometer'"] = df["b'Pyranometer'"].astype(float)
            
                print("Sending " + log_prefix + " data points")
                
                with client.write_api() as write_api:
                    try:
                        write_api.write(
                            record=df,
                            bucket=args.bucket,
                            data_frame_measurement_name=dev_hostname,
                            data_frame_tag_columns=["zakbox"],
                            data_frame_timestamp_column="timestamp",
                        )
                    except InfluxDBError as e:
                        print(e)
    print("Finished Uploading to InfluxDB.")

if __name__ == "__main__":
    main()
