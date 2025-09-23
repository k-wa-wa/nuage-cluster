package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
)

type RequestData struct {
	NetworkInterfaces []struct {
		MAC string `json:"mac"`
	} `json:"network_interfaces"`
}

func handleAnswer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Failed to read request body", http.StatusInternalServerError)
		return
	}
	fmt.Printf("%+v\n", body)

	var reqData RequestData
	err = json.Unmarshal(body, &reqData)
	if err != nil {
		http.Error(w, "Failed to parse JSON", http.StatusBadRequest)
		return
	}

	if len(reqData.NetworkInterfaces) == 0 {
		http.Error(w, "No Mac address", http.StatusBadRequest)
		return
	}

	mac := reqData.NetworkInterfaces[0].MAC
	fmt.Println(mac)

	responseString := `
[global]
keyboard = "jp"
country = "jp"
fqdn.source = "from-dhcp"
mailto = "mail@example.com"
timezone = "Asia/Tokyo"
root-password = "password"
reboot-mode = "power-off"

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
`
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(responseString))
}

func main() {
	http.HandleFunc("/pve-answer.toml", handleAnswer)

	fmt.Println("Server listening on http://0.0.0.0:5000...")
	log.Fatal(http.ListenAndServe(":5000", nil))
}
