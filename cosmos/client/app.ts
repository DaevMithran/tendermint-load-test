import { SigningStargateClient, MsgSendEncodeObject, StargateClient } from "@cosmjs/stargate"
import { readFile } from "fs/promises"
import { DirectSecp256k1HdWallet, OfflineDirectSigner } from "@cosmjs/proto-signing"
import * as dotenv from "dotenv"
import axios from 'axios'

dotenv.config()
const rpcs = process.env.rpc.split(',')
console.log(rpcs)

let count=1

interface clients {
    addr: string,
    client: SigningStargateClient
}

const signerClients: clients[] = []

const runTest = async () => {

    const n=200
    const T=15
    const queryClient = await StargateClient.connect(rpcs[0])
    const h1 = await queryClient.getHeight()
    
    //create all signer clients
    for (let i=0;i<n;i++) {
        const signer = await getSignerFromMnemonic(i)
        const client = await SigningStargateClient.connectWithSigner(rpcs[i%4], signer)
        const addr = (await readFile(`../keys/node-${i}_ADDRESS.txt`)).toString()
        signerClients.push({
            addr,
            client
        })
    }

    // send token ntimes every x seconds
    const startTime = Date.now()
    var timeout = setInterval(async () => {
        sendTokens(n)
        if (Date.now()-startTime>(T+5)*1000) {
            clearInterval(timeout)
            const stopTime = Date.now()
            console.log("Fetching height")
            const h2 = await queryClient.getHeight()
            console.log("Heights", h1, h2)
            const totaltxns = await calculateTransactions(h1, h2)
            console.log("totaltxns:", totaltxns)
            console.log("time", (stopTime-startTime)/1000)
            return
        }
    }, 1000)
    return
}

const sendTokens = async (n: number) => {
    for (let i=0;i<n-1;i++) {
        // console.log(`sending ${count}`)
        signerClients[i].client.sendTokens(
            signerClients[i].addr,
            signerClients[i+1].addr,
            [{denom: "stake", amount: "1"}],
            {
              amount: [],
              gas: "2000000",
            },
            `${count++}`
            ).catch(()=>{console.log(i)})
    }
}

// custom messages
const customMessages = async (n: number) => {
    for (let i=0;i<n-1;i++) {
        // console.log(`sending ${count}`)
        const sendMsg: MsgSendEncodeObject = {
            typeUrl: "/cosmos.bank.v1beta1.MsgSend", 
            value: {
              fromAddress: signerClients[i].addr,
              toAddress: signerClients[i+1].addr,
              amount: [{denom: "stake", amount: "10"}],
            },
          }

        signerClients[i].client.signAndBroadcast(signerClients[i].addr, [sendMsg], { amount: [], gas: "2000000"}, `${count++}`).catch(()=>{})
    }
}

const getSignerFromMnemonic = async (index: number): Promise<OfflineDirectSigner> => {
    return DirectSecp256k1HdWallet.fromMnemonic(`${(await readFile(`../keys/node-${index}_MNEMONIC.txt`)).toString()}`, {
        prefix: "cosmos"
    })
}


const calculateTransactions = async (h1: number, h2: number) : Promise<number> => {
    let count=0;
    // for (let x=h1; x<=h2+20;x+=20) 
    // {
    const {data} = await axios.get(`${rpcs[1]}/blockchain?minHeight=${h1+3}&maxHeight=${h2+3}`) 
    data.result.block_metas.forEach(block=> {
        count += parseInt(block.num_txs)
    })
    // }
    return count
}


const makeRandomAddress = async () => {
    const wallet = await DirectSecp256k1HdWallet.generate()
    return (await wallet.getAccounts())[0].address
}

runTest()